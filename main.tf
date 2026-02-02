locals {
  # Filter subnets that have a project_id assigned and flatten them
  all_subnets = flatten([
    for subnet_key, subnet in var.subnets : [
      {
        subnet_key = subnet_key
        project_id = subnet.project_id
        subnet     = subnet
        key        = "${subnet.project_id}/${subnet_key}"
      }
    ] if subnet.project_id != ""
  ])

  # Flatten IAM members for subnets with project_ids
  subnet_iam_members = flatten([
    for subnet_key, subnet in var.subnets : [
      for service_account in try(var.project_service_accounts[subnet.project_id], []) : {
        subnet_key      = subnet_key
        project_id      = subnet.project_id
        subnet_name     = subnet.name
        region          = subnet.region
        service_account = service_account
      }
    ] if subnet.project_id != "" && subnet.name != "" && subnet.region != ""
  ])

  # Extract GKE service accounts for host project IAM - only from projects with active subnets
  gke_service_accounts = flatten([
    for subnet_key, subnet in var.subnets : [
      for service_account in try(var.project_service_accounts[subnet.project_id], []) : service_account
      if strcontains(service_account, "@container-engine-robot.iam.gserviceaccount.com")
    ] if subnet.project_id != "" && subnet.name != "" && subnet.region != ""
  ])

  # Create proxy-only subnet configurations from regions
  proxy_only_subnets = [
    for region_key, region_config in var.regions : {
      region_key    = region_key
      region_config = region_config
    } if region_config.proxy_only_subnet != "" && region_config.proxy_only_subnet != null
  ]
}

# Shared VPC Network
resource "google_compute_network" "shared_vpc_network" {
  name                    = var.name
  auto_create_subnetworks = false
  project                 = var.project_id
}

# Host Project
resource "google_compute_shared_vpc_host_project" "host" {
  project = var.project_id
}

# Service Projects - attach service projects to the host project
resource "google_compute_shared_vpc_service_project" "service_project" {
  for_each        = toset([for item in local.all_subnets : item.project_id])
  host_project    = google_compute_shared_vpc_host_project.host.project
  service_project = each.value
}

# Subnets
resource "google_compute_subnetwork" "network-with-private-secondary-ip-ranges" {
  for_each = {
    for item in local.all_subnets :
    item.key => item
  }

  name                     = each.value.subnet.name
  ip_cidr_range            = each.value.subnet.node_ip_cidr_range
  region                   = each.value.subnet.region
  network                  = google_compute_network.shared_vpc_network.id
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = each.value.subnet.pod_ip_cidr_range
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = each.value.subnet.service_ip_cidr_range
  }
}

# Subnet IAM Permissions
resource "google_compute_subnetwork_iam_member" "subnet_iam" {
  for_each = {
    for item in local.subnet_iam_members :
    "${item.subnet_key}-${item.service_account}" => item
  }

  project    = var.project_id
  region     = each.value.region
  subnetwork = each.value.subnet_name
  role       = "roles/compute.networkUser"
  member     = each.value.service_account

  # Ensure subnets are created before setting IAM permissions
  depends_on = [
    google_compute_subnetwork.network-with-private-secondary-ip-ranges
  ]
}

# GKE Service Account IAM Permissions for Shared VPC
resource "google_project_iam_member" "gke_host_service_agent" {
  for_each = toset(local.gke_service_accounts)
  project  = var.project_id
  role     = "roles/container.hostServiceAgentUser"
  member   = each.value
}

# firewall to allow cluster to cluster communication
resource "google_compute_firewall" "cluster_to_cluster_firewall" {
  for_each = var.cluster_to_cluster_firewall_rules
  name     = each.value.name
  network  = google_compute_network.shared_vpc_network.id
  project  = var.project_id

  source_ranges = each.value.source_ranges

  dynamic "allow" {
    for_each = each.value.allow
    content {
      protocol = allow.value.protocol
      ports    = try(allow.value.ports, [])
    }
  }
}

# Cloud DNS
resource "google_dns_managed_zone" "private_zone" {
  name       = "${var.name}-internal-dns-zone"
  dns_name   = var.internal_dns_name
  project    = var.project_id
  visibility = "private"
  private_visibility_config {
    networks {
      network_url = google_compute_network.shared_vpc_network.id
    }
  }
}

# Reserve an internal range for Google-managed services (PSA)
resource "google_compute_global_address" "psa_range" {
  name          = "google-managed-services-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = split("/", var.psa_range)[0] # Extract IP address from CIDR
  prefix_length = split("/", var.psa_range)[1] # Extract prefix length from CIDR
  network       = google_compute_network.shared_vpc_network.id
}

# Create PSA connection to Service Networking
resource "google_service_networking_connection" "psa_connection" {
  network                 = google_compute_network.shared_vpc_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa_range.name]
}

# Proxy-only subnet for cross-region managed proxy
resource "google_compute_subnetwork" "proxy_only_subnet" {
  for_each = {
    for item in local.proxy_only_subnets :
    item.region_key => item
  }

  name          = "${each.value.region_key}-proxy-only"
  description   = "Used for internal load balancers"
  ip_cidr_range = each.value.region_config.proxy_only_subnet
  region        = each.value.region_key
  network       = google_compute_network.shared_vpc_network.id
  purpose       = "GLOBAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

# ============================================================================
# Observability Infrastructure (Thanos/Loki/Tempo)
# Automatically creates static IPs, DNS, and firewall rules for product subnets
# ============================================================================

locals {
  # Automatically derive monitoring cluster pod CIDR from monitoring project's subnet
  monitoring_pod_cidr = var.observability_config.enabled && var.observability_config.monitoring_project_id != "" ? (
    try([
      for subnet_key, subnet in var.subnets :
      subnet.pod_ip_cidr_range
      if subnet.project_id == var.observability_config.monitoring_project_id
    ][0], "")
  ) : ""

  # Filter active product subnets (exclude monitoring project and empty project_ids)
  observability_subnets = var.observability_config.enabled ? {
    for subnet_key, subnet in var.subnets :
    subnet_key => subnet
    if subnet.project_id != "" && subnet.project_id != var.observability_config.monitoring_project_id
  } : {}

  # Extract product name from subnet name (e.g., "peak-money-staging-us-west1" → "peak-money")
  # Assumes naming pattern: {product}-(staging|preview|production|beta)-{region}
  observability_endpoints = var.observability_config.enabled ? flatten([
    for subnet_key, subnet in local.observability_subnets : [
      for service_key, service in var.observability_config.services : {
        key         = "${subnet_key}-${service_key}"
        subnet_key  = subnet_key
        service_key = service_key
        project_id  = subnet.project_id
        subnet_name = subnet.name
        region      = subnet.region
        # Extract product: match pattern {product}-(staging|preview|production|beta)-{region} and take product
        product = regex("^(.+)-(staging|preview|production|beta)-", subnet.name)[0]
        # Calculate IP: take node subnet base + offset
        ip_address = cidrhost(subnet.node_ip_cidr_range, service.ip_offset)
        dns_name   = "${service.dns_prefix}.${subnet.region}.${regex("^(.+)-(staging|preview|production|beta)-", subnet.name)[0]}.${var.internal_dns_name}"
        ports      = service.ports
        enabled    = service.enabled
        node_cidr  = subnet.node_ip_cidr_range
      } if service.enabled
    ]
  ]) : []

  # Auto-discover all products that have observability endpoints enabled
  products_with_observability = var.observability_config.enabled ? distinct([
    for endpoint in local.observability_endpoints :
    endpoint.product
  ]) : []

  # Product observability firewall rules - allow both SRE monitoring and intra-product access to observability endpoints
  product_observability_rules = {
    for product in local.products_with_observability : product => {
      # Source: SRE monitoring pods + all product pods
      source_cidrs = distinct(concat(
        local.monitoring_pod_cidr != "" ? [local.monitoring_pod_cidr] : [],
        [for subnet in var.subnets : subnet.pod_ip_cidr_range if subnet.project_id != "" && strcontains(lower(subnet.project_id), lower(product))]
      ))

      # Destination: All observability endpoint IPs for this product
      endpoint_ips = distinct([
        for endpoint in local.observability_endpoints :
        "${endpoint.ip_address}/32"
        if lower(endpoint.product) == lower(product)
      ])

      # All unique ports used by observability endpoints (flatten since each endpoint has a list of ports)
      ports = distinct(flatten([
        for endpoint in local.observability_endpoints : [
          for port in endpoint.ports :
          tostring(port)
        ]
        if lower(endpoint.product) == lower(product)
      ]))
    }
  }
}

# Static IPs for observability endpoints
resource "google_compute_address" "observability_endpoint" {
  for_each = var.observability_config.enabled ? {
    for endpoint in local.observability_endpoints :
    endpoint.key => endpoint
  } : {}

  project = each.value.project_id
  # Use override name if provided, otherwise use default format
  name         = "${each.value.service_key}-${each.value.region}-${each.value.product}"
  region       = each.value.region
  subnetwork   = google_compute_subnetwork.network-with-private-secondary-ip-ranges["${each.value.project_id}/${each.value.subnet_key}"].id
  address_type = "INTERNAL"
  address      = each.value.ip_address
  purpose      = "GCE_ENDPOINT"
  description  = "Static IP for ${each.value.service_key} in ${each.value.product} ${each.value.region}"
}

# DNS records for observability endpoints
resource "google_dns_record_set" "observability_endpoint" {
  for_each = var.observability_config.enabled ? {
    for endpoint in local.observability_endpoints :
    endpoint.key => endpoint
  } : {}

  project      = var.project_id
  managed_zone = google_dns_managed_zone.private_zone.name
  name         = each.value.dns_name
  type         = "A"
  ttl          = 300

  rrdatas = [google_compute_address.observability_endpoint[each.key].address]
}

# Product observability firewall rules - allow both SRE monitoring and intra-product access
resource "google_compute_firewall" "product_observability" {
  for_each = {
    for product, rule in local.product_observability_rules :
    product => rule
    if length(rule.source_cidrs) > 0 && length(rule.endpoint_ips) > 0
  }

  project     = var.project_id
  name        = "allow-${each.key}-observability"
  network     = google_compute_network.shared_vpc_network.id
  description = "Allow SRE monitoring and ${each.key} pods to reach ${each.key} observability endpoints (tempo/loki/thanos)"

  source_ranges      = each.value.source_cidrs
  destination_ranges = each.value.endpoint_ips

  allow {
    protocol = "tcp"
    ports    = each.value.ports
  }

  priority = 1000
}
