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
  "allow-sql" = {
    name        = "allow-sql"
    protocol    = "tcp"
    ports       = ["5432"]
    priority    = null
    description = "Allow SQL"
    source_ip_ranges = [
      "10.90.0.0/16",
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
    name               = "postgresql-pool"
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
    name               = "scheduler-pool"
    machine_type       = "e2-small"
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
  all             = []
  default-pool    = []
  postgresql-pool = []
  scheduler-pool  = []
}

secrets_map = {
  postgresql = {
    secret_id          = "postgresql-password"
    chars_count        = 32
    use_special_charts = true
  }
}

postgresql_settings = {
  create                 = true
  name                   = "postgres"
  namespace              = "database"
  image                  = "postgres"
  version                = "16-alpine"
  replicas               = 1
  username               = "postgres"
  database               = "postgres"
  limits_cpu             = "1000m"
  limits_mem             = "2Gi"
  requests_cpu           = "250m"
  requests_mem           = "256Mi"
  revision_history       = 10
  service_type           = "ClusterIP"
  service_protocol       = "TCP"
  service_port           = 5432
  service_traffic_policy = "Cluster"
}

postgresql_backup = {
  enabled            = true
  name               = "ribc-pg-backup"
  image              = "ribc-pg-backup"
  version            = "1.0"
  cronjob_schedule   = "0 1 * * *"
  max_retention_days = "5"
}

scheduler_settings = {
  create           = true
  name             = "ribc-scheduler"
  namespace        = "scheduler"
  image            = "ribc-scheduler"
  version          = "1.0"
  cronjob_schedule = "0 1 * * *"
  input_folder     = "/app/input"
  output_folder    = "/app/output"
  pgconninfo       = "dbname=ribc user=scheduler host=10.18.0.26 password=123456"
  ftp_url          = "ftp://ribc.com.sg/schedule"
}
