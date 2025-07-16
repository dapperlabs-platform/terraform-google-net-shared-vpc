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

variable "name" {
  description = "Name of the shared VPC network"
  type        = string
}

variable "project_id" {
  description = "The host project ID that will own the shared VPC"
  type        = string
}

variable "subnets" {
  description = "Map of subnet configurations. Only subnets with project_id assigned will be created."
  type = map(object({
    project_id            = string
    name                  = string
    region                = string
    master_ip_cidr_range  = string
    node_ip_cidr_range    = string
    pod_ip_cidr_range     = string
    service_ip_cidr_range = string
  }))
  default = {}
}

variable "project_service_accounts" {
  description = "Map of project_id to list of service accounts that will get IAM permissions on subnets"
  type        = map(list(string))
  default     = {}
}

variable "description" {
  description = "Description of the shared VPC network"
  type        = string
  default     = "Shared VPC network for multiple service projects"
}

variable "auto_create_subnetworks" {
  description = "When set to true, the network is created in auto subnet mode"
  type        = bool
  default     = false
}

variable "routing_mode" {
  description = "The network routing mode (REGIONAL or GLOBAL)"
  type        = string
  default     = "REGIONAL"
  validation {
    condition     = contains(["REGIONAL", "GLOBAL"], var.routing_mode)
    error_message = "Routing mode must be either REGIONAL or GLOBAL."
  }
}

variable "mtu" {
  description = "Maximum Transmission Unit in bytes"
  type        = number
  default     = 1460
  validation {
    condition     = var.mtu >= 1280 && var.mtu <= 8896
    error_message = "MTU must be between 1280 and 8896."
  }
}

variable "enable_ula_internal_ipv6" {
  description = "Enable ULA internal IPv6 on this network"
  type        = bool
  default     = false
}

variable "internal_ipv6_range" {
  description = "When enabling ula internal ipv6, caller optionally can specify the /48 range they want from the google defined /48 range"
  type        = string
  default     = null
}

variable "network_firewall_policy_enforcement_order" {
  description = "Set the order that firewall policies and firewall rules are evaluated"
  type        = string
  default     = "AFTER_CLASSIC_FIREWALL"
  validation {
    condition     = contains(["AFTER_CLASSIC_FIREWALL", "BEFORE_CLASSIC_FIREWALL"], var.network_firewall_policy_enforcement_order)
    error_message = "Network firewall policy enforcement order must be either AFTER_CLASSIC_FIREWALL or BEFORE_CLASSIC_FIREWALL."
  }
}

variable "delete_default_routes_on_create" {
  description = "If set to true, default routes (0.0.0.0/0) will be deleted immediately after network creation"
  type        = bool
  default     = false
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in this network"
  type        = bool
  default     = false
}

variable "enable_dns" {
  description = "Enable DNS resolution in this network"
  type        = bool
  default     = true
}

variable "dns_policy" {
  description = "DNS policy configuration for the network"
  type = object({
    enable_inbound_forwarding = optional(bool, false)
    enable_logging            = optional(bool, false)
    alternative_name_servers  = optional(list(string), [])
    default_nameservers       = optional(list(string), [])
  })
  default = {}
}

variable "router_asn" {
  description = "ASN for the Cloud Router"
  type        = number
  default     = 64514
}

variable "router_advertise_config" {
  description = "Router advertisement configuration"
  type = object({
    advertise_mode    = optional(string, "DEFAULT")
    advertised_groups = optional(list(string), [])
    advertised_ip_ranges = optional(list(object({
      range       = string
      description = optional(string, "")
    })), [])
  })
  default = {}
}

variable "nat_config" {
  description = "NAT configuration for the routers"
  type = object({
    nat_ip_allocate_option              = optional(string, "AUTO_ONLY")
    source_subnetwork_ip_ranges_to_nat  = optional(string, "ALL_SUBNETWORKS_ALL_IP_RANGES")
    enable_endpoint_independent_mapping = optional(bool, null)
    enable_dynamic_port_allocation      = optional(bool, null)
    min_ports_per_vm                    = optional(number, null)
    max_ports_per_vm                    = optional(number, null)
    enable_log_config                   = optional(bool, true)
    log_config_filter                   = optional(string, "ERRORS_ONLY")
  })
  default = {}
}

variable "subnet_iam_roles" {
  description = "Map of IAM roles to assign to service accounts on subnets"
  type        = map(list(string))
  default = {
    "roles/compute.networkUser" = []
  }
}

variable "timeouts" {
  description = "Custom timeout options for resources"
  type = object({
    create = optional(string, "10m")
    update = optional(string, "10m")
    delete = optional(string, "10m")
  })
  default = {}
}
