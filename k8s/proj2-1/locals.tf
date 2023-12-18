locals {
  region           = var.cluster_settings.regional ? var.region : join("-", slice(split("-", var.cluster_settings.zones[0]), 0, 2))
  zone_count       = length(var.cluster_settings.zones)
  location         = var.cluster_settings.regional ? var.region : var.cluster_settings.zones[0]
  node_locations   = var.cluster_settings.regional ? coalescelist(compact(var.cluster_settings.zones), try(sort(random_shuffle.available_zones[0].result), [])) : slice(var.cluster_settings.zones, 1, length(var.cluster_settings.zones))
  service_accounts = jsondecode(file("${path.module}/files/service_accounts.json"))["serviceAccounts"]

  sa_roles_flattened = flatten([
    for sa in local.service_accounts : [
      for role in sa["roles"] : {
        account_id   = sa["account_id"]
        display_name = sa["display_name"]
        role         = role
      }
      if sa["create"]
    ]
  ])

  autoscaling_resource_limits = var.cluster_autoscaling.enabled ? concat([{
    resource_type = "cpu"
    minimum       = var.cluster_autoscaling.min_cpu_cores
    maximum       = var.cluster_autoscaling.max_cpu_cores
    }, {
    resource_type = "memory"
    minimum       = var.cluster_autoscaling.min_memory_gb
    maximum       = var.cluster_autoscaling.max_memory_gb
  }], var.cluster_autoscaling.gpu_resources) : []
}
