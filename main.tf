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

# proxy-only subnet
resource "google_compute_subnetwork" "proxy_only_subnet" {
  for_each = {
    for item in local.all_subnets :
    item.key => item
  }
  name          = "${each.value.subnet.name}-proxy-only"
  ip_cidr_range = each.value.subnet.proxy_only_subnet_range
  region        = each.value.subnet.region
  network       = google_compute_network.shared_vpc_network.id
  purpose       = "GLOBAL_MANAGED_PROXY"
}
