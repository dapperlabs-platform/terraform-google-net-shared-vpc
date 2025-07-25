# Terraform Google Shared VPC for GKE

This module creates and configures a Google Cloud Shared VPC network specifically designed for hosting GKE (Google Kubernetes Engine) clusters across multiple service projects.

## Features

- **Shared VPC Network**: Creates a host project with shared VPC and attaches service projects
- **GKE-Optimized Subnets**: Creates subnets with secondary IP ranges for GKE pods and services
- **Automatic IAM Management**: 
  - Grants `roles/compute.networkUser` to service accounts on their respective subnets
  - Automatically detects and grants `roles/container.hostServiceAgentUser` to GKE service accounts
- **Cluster-to-Cluster Firewall Rules**: Configurable firewall rules for inter-cluster communication
- **Private DNS Zone**: Creates internal DNS zone for cluster communication

## Usage

### Basic GKE Shared VPC Setup

```hcl
module "shared_vpc" {
  source = "github.com/dapperlabs-platform/terraform-google-net-shared-vpc?ref=tag"
  
  project_id        = "my-host-project"
  name              = "gke-shared-vpc"
  internal_dns_name = "internal.example.com."
  
  subnets = {
    "us-central1-gke" = {
      project_id            = "my-service-project-1"
      name                  = "gke-subnet-us-central1"
      region                = "us-central1"
      master_ip_cidr_range  = "10.0.0.0/28"    # GKE master nodes
      node_ip_cidr_range    = "10.1.0.0/24"    # GKE worker nodes
      pod_ip_cidr_range     = "10.2.0.0/16"    # Kubernetes pods
      service_ip_cidr_range = "10.3.0.0/24"    # Kubernetes services
    },
    "us-west1-gke" = {
      project_id            = "my-service-project-2"
      name                  = "gke-subnet-us-west1"
      region                = "us-west1"
      master_ip_cidr_range  = "10.4.0.0/28"
      node_ip_cidr_range    = "10.5.0.0/24"
      pod_ip_cidr_range     = "10.6.0.0/16"
      service_ip_cidr_range = "10.7.0.0/24"
    }
  }
  
  project_service_accounts = {
    "my-service-project-1" = [
      "serviceAccount:123456789@cloudservices.gserviceaccount.com",
      "serviceAccount:gke-workload-runner@my-service-project-1.iam.gserviceaccount.com",
      "serviceAccount:service-123456789@container-engine-robot.iam.gserviceaccount.com"
    ],
    "my-service-project-2" = [
      "serviceAccount:987654321@cloudservices.gserviceaccount.com",
      "serviceAccount:gke-workload-runner@my-service-project-2.iam.gserviceaccount.com",
      "serviceAccount:service-987654321@container-engine-robot.iam.gserviceaccount.com"
    ]
  }
}
```

### With Cluster-to-Cluster Firewall Rules

```hcl
module "shared_vpc" {
  source = "github.com/dapperlabs-platform/terraform-google-net-shared-vpc?ref=tag"
  
  # ... basic configuration ...
  
  cluster_to_cluster_firewall_rules = {
    "allow-cluster-communication" = {
      name          = "allow-gke-cluster-communication"
      source_ranges = ["10.2.0.0/16", "10.6.0.0/16"]  # Pod CIDR ranges
      allow = [
        {
          protocol = "tcp"
          ports    = ["443", "8080", "9090"]
        },
        {
          protocol = "udp"
          ports    = ["53"]
        }
      ]
    }
  }
}
```

## Subnet Configuration

Each subnet in the `subnets` map must include GKE-specific CIDR ranges:

| Field | Description | Example |
|-------|-------------|---------|
| `project_id` | Service project that will use this subnet | `"my-gke-project"` |
| `name` | Subnet name | `"gke-subnet-us-central1"` |
| `region` | GCP region | `"us-central1"` |
| `master_ip_cidr_range` | CIDR for GKE control plane | `"10.0.0.0/28"` |
| `node_ip_cidr_range` | CIDR for GKE worker nodes (primary subnet range) | `"10.1.0.0/24"` |
| `pod_ip_cidr_range` | CIDR for Kubernetes pods (secondary range) | `"10.2.0.0/16"` |
| `service_ip_cidr_range` | CIDR for Kubernetes services (secondary range) | `"10.3.0.0/24"` |

## Service Accounts

The `project_service_accounts` map should include all service accounts that need network access:

- **Cloud Services Account**: `{PROJECT_NUMBER}@cloudservices.gserviceaccount.com`
- **Custom Service Accounts**: `custom-sa@{PROJECT_ID}.iam.gserviceaccount.com`
- **GKE Service Account**: `service-{PROJECT_NUMBER}@container-engine-robot.iam.gserviceaccount.com`

The module automatically:
1. Grants `roles/compute.networkUser` on subnets to all listed service accounts
2. Detects GKE service accounts (ending in `@container-engine-robot.iam.gserviceaccount.com`) and grants them `roles/container.hostServiceAgentUser` on the host project

## Outputs

| Name | Description |
|------|-------------|
| `network_id` | The shared VPC network ID |
| `network_name` | The shared VPC network name |
| `host_project_id` | The host project ID |
| `service_project_ids` | List of attached service project IDs |
| `subnet_ids` | Map of subnet IDs by subnet key |
| `subnet_names` | Map of subnet names by subnet key |
| `gke_service_accounts` | List of GKE service accounts that received permissions |

## Requirements

- Host project must have the Compute Engine API enabled
- Service projects must have the Container API and Compute Engine API enabled
- Terraform user must have the following roles:
  - `roles/compute.xpnAdmin` on the host project
  - `roles/compute.networkAdmin` on the host project
  - `roles/resourcemanager.projectIamAdmin` on the host project
  - `roles/compute.networkUser` on service projects

## Important Notes

- This module is specifically designed for GKE clusters using shared VPC
- Each subnet includes required secondary IP ranges for Kubernetes pods and services
- GKE service account permissions are automatically managed
- Only one subnet per service project per region is supported by this module design
