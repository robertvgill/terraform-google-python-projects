# Set up variables
provider "google" {
  project = var.project
  region  = var.region
}

data "google_project" "project" {
  project_id = var.project
}

variable "project" {
  description = "Google Cloud Project ID"
  type        = string
}

variable "region" {
  description = "Google Cloud Region"
  type        = string
}

variable "service" {
  description = "The name of the service"
  type        = string
}

variable "organization" {
  description = "The name of the organization"
  type        = string
}

variable "subnetwork_map" {
  description = "VPC Subnetworks"
  type = map(object({
    name = string
    cidr = string
  }))
}

variable "secondary_ranges" {
  description = "Secondary ranges that will be used in some of the subnets"
  type = map(list(object({
    range_name    = string,
    ip_cidr_range = string
  })))
}

variable "firewall_rules" {
  description = "The firewall rules"
  type = map(object({
    name             = string,
    protocol         = string,
    ports            = list(string),
    priority         = number,
    description      = string,
    source_ip_ranges = list(string)
  }))
}

variable "cluster_settings" {
  description = "The settings for the GKE cluster"
  type = object({
    create                           = bool
    regional                         = bool
    zones                            = list(string)
    ip_cidr_range                    = string
    initial_node_count               = number
    deletion_protection              = bool
    vertical_pod_autoscaling_enabled = bool
  })
}

variable "cluster_autoscaling" {
  description = "Cluster autoscaling configuration"
  type = object({
    enabled         = bool
    location_policy = optional(string)
    min_cpu_cores   = number
    max_cpu_cores   = number
    min_memory_gb   = number
    max_memory_gb   = number
    gpu_resources = list(object({
      resource_type = string
      minimum       = number
      maximum       = number
    }))
    auto_repair  = bool
    auto_upgrade = bool
    disk_size    = optional(number)
    disk_type    = optional(string)
  })
}

variable "node_pools" {
  description = "List of maps containing node pools"
  type        = list(map(any))
}

variable "node_pools_taints" {
  description = "Map of lists containing node taints per node-pool name"
  type        = map(list(object({ key = string, value = string, effect = string })))
}
