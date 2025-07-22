/**
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

output "network_id" {
  description = "The ID of the shared VPC network"
  value       = google_compute_network.shared_vpc_network.id
}

output "network_self_link" {
  description = "The self-link of the shared VPC network"
  value       = google_compute_network.shared_vpc_network.self_link
}

output "network_name" {
  description = "The name of the shared VPC network"
  value       = google_compute_network.shared_vpc_network.name
}

output "host_project_id" {
  description = "The host project ID"
  value       = google_compute_shared_vpc_host_project.host.project
}

output "service_project_ids" {
  description = "List of service project IDs attached to the shared VPC"
  value       = [for project in google_compute_shared_vpc_service_project.service_project : project.service_project]
}

output "subnet_ids" {
  description = "Map of subnet IDs by subnet key"
  value       = { for k, v in google_compute_subnetwork.network-with-private-secondary-ip-ranges : k => v.id }
}

output "subnet_self_links" {
  description = "Map of subnet self-links by subnet key"
  value       = { for k, v in google_compute_subnetwork.network-with-private-secondary-ip-ranges : k => v.self_link }
}

output "subnet_names" {
  description = "Map of subnet names by subnet key"
  value       = { for k, v in google_compute_subnetwork.network-with-private-secondary-ip-ranges : k => v.name }
}

output "subnet_regions" {
  description = "Map of subnet regions by subnet key"
  value       = { for k, v in google_compute_subnetwork.network-with-private-secondary-ip-ranges : k => v.region }
}

output "subnet_ip_cidr_ranges" {
  description = "Map of subnet primary IP CIDR ranges by subnet key"
  value       = { for k, v in google_compute_subnetwork.network-with-private-secondary-ip-ranges : k => v.ip_cidr_range }
}

output "subnet_secondary_ip_ranges" {
  description = "Map of subnet secondary IP ranges by subnet key"
  value       = { for k, v in google_compute_subnetwork.network-with-private-secondary-ip-ranges : k => v.secondary_ip_range }
}

#output "router_ids" {
#  description = "Map of router IDs by region"
#  value       = { for k, v in google_compute_router.nat : k => v.id }
#}
#
#output "router_names" {
#  description = "Map of router names by region"
#  value       = { for k, v in google_compute_router.nat : k => v.name }
#}
#
#output "router_self_links" {
#  description = "Map of router self-links by region"
#  value       = { for k, v in google_compute_router.nat : k => v.self_link }
#}
#
#output "nat_ids" {
#  description = "Map of NAT gateway IDs by region"
#  value       = { for k, v in google_compute_router_nat.nat : k => v.id }
#}
#
#output "nat_names" {
#  description = "Map of NAT gateway names by region"
#  value       = { for k, v in google_compute_router_nat.nat : k => v.name }
#}

output "subnet_iam_members" {
  description = "Map of subnet IAM members by subnet key and service account"
  value       = { for k, v in google_compute_subnetwork_iam_member.subnet_iam : k => v.member }
}

output "subnet_iam_debug" {
  description = "Debug information about subnet IAM configuration"
  value = {
    project_service_accounts = var.project_service_accounts
    subnet_iam_members_local = local.subnet_iam_members
    subnet_iam_resources = {
      for k, v in google_compute_subnetwork_iam_member.subnet_iam : k => {
        project    = v.project
        region     = v.region
        subnetwork = v.subnetwork
        role       = v.role
        member     = v.member
      }
    }
  }
}

output "all_subnets" {
  description = "Complete subnet information including project associations"
  value = {
    for k, v in google_compute_subnetwork.network-with-private-secondary-ip-ranges : k => {
      id                  = v.id
      name                = v.name
      region              = v.region
      ip_cidr_range       = v.ip_cidr_range
      secondary_ip_ranges = v.secondary_ip_range
      self_link           = v.self_link
      network             = v.network
    }
  }
}

output "network_summary" {
  description = "Summary of the shared VPC network configuration"
  value = {
    network_id       = google_compute_network.shared_vpc_network.id
    network_name     = google_compute_network.shared_vpc_network.name
    host_project     = google_compute_shared_vpc_host_project.host.project
    service_projects = [for project in google_compute_shared_vpc_service_project.service_project : project.service_project]
    subnet_count     = length(google_compute_subnetwork.network-with-private-secondary-ip-ranges)
    #router_count      = length(google_compute_router.nat)
    #nat_count         = length(google_compute_router_nat.nat)
    iam_binding_count = length(google_compute_subnetwork_iam_member.subnet_iam)
  }
}
