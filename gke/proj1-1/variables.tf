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

variable "fqdn" {
  description = "The name of FQDN"
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
