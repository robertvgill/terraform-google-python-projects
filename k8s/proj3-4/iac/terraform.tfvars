region       = "asia-southeast1"
service      = "gke"
organization = "ribc"

firewall_rules = {
  "allow-https" = {
    name        = "allow-https"
    protocol    = "tcp"
    ports       = ["443"]
    priority    = null
    tags        = ["https"]
    description = "Allow HTTPS"
    source_ip_ranges = [
      "0.0.0.0/0",
    ]
  },
}

subnetwork_map = {
  "gke" = {
    name = "gke"
    cidr = "10.0.0.0/18"
  }
  "wkl" = {
    name = "wkl"
    cidr = "10.90.0.0/16"
  }
}

secondary_ranges = {
  gke = [
    {
      range_name    = "gke-pod-range"
      ip_cidr_range = "10.48.0.0/14"
    },

    {
      range_name    = "gke-svc-range"
      ip_cidr_range = "10.52.0.0/20"
  }, ]

  wkl = []
}

cluster_settings = {
  create   = true
  regional = true
  zones = [
    "asia-southeast1-a",
    "asia-southeast1-b",
    "asia-southeast1-c"
  ]
  ip_cidr_range                    = "10.82.0.0/16"
  initial_node_count               = 1
  deletion_protection              = false
  vertical_pod_autoscaling_enabled = true
}

cluster_autoscaling = {
  enabled         = true
  location_policy = "BALANCED"
  max_cpu_cores   = 256
  min_cpu_cores   = 1
  max_memory_gb   = 512
  min_memory_gb   = 2
  gpu_resources   = []
  auto_repair     = true
  auto_upgrade    = true
  disk_size       = 100
  disk_type       = "pd-standard"
}

node_pools = [
  {
    create             = true
    name               = "default-pool"
    machine_type       = "e2-medium"
    min_count          = 1
    max_count          = 2
    local_ssd_count    = 0
    spot               = false
    disk_size_gb       = 100
    disk_type          = "pd-standard"
    image_type         = "COS_CONTAINERD"
    enable_gcfs        = false
    enable_gvnic       = false
    logging_variant    = "DEFAULT"
    auto_repair        = true
    auto_upgrade       = true
    preemptible        = false
    initial_node_count = 1
  },
  {
    create             = true
    name               = "application-pool"
    machine_type       = "e2-medium"
    min_count          = 1
    max_count          = 2
    local_ssd_count    = 0
    spot               = false
    disk_size_gb       = 100
    disk_type          = "pd-standard"
    image_type         = "COS_CONTAINERD"
    enable_gcfs        = false
    enable_gvnic       = false
    logging_variant    = "DEFAULT"
    auto_repair        = true
    auto_upgrade       = true
    preemptible        = false
    initial_node_count = 1
  },
]

node_pools_taints = {
  all              = []
  default-pool     = []
  application-pool = []
}

application_settings = {
  create                 = true
  name                   = "traffic-detection"
  namespace              = "application"
  image                  = "traffic-detection"
  version                = "1.0"
  replicas               = 3
  limits_cpu             = "250m"
  limits_mem             = "256Mi"
  requests_cpu           = "100m"
  requests_mem           = "64Mi"
  revision_history       = 10
  service_type           = "ClusterIP"
  service_protocol       = "UDP"
  service_port           = 8000
  service_traffic_policy = "Cluster"
  socket_path            = "/tmp/datagram.sock"
}
