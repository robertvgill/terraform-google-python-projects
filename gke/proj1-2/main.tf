# Step 1: Activate service APIs
resource "google_project_service" "api_services" {
  project = var.project
  service = each.value
  for_each = toset([
    "certificatemanager.googleapis.com", # Certificate Manager API
    "compute.googleapis.com",            # Compute Engine API
    "logging.googleapis.com",            # Cloud Logging API
    "secretmanager.googleapis.com",      # Secret Manager API
    "servicenetworking.googleapis.com",  # Service Networking API
  ])

  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_dependent_services = false
  disable_on_destroy         = false
}

# Step 2: Create a custom Service Account
resource "google_service_account" "service_account" {
  for_each = {
    for idx, sa in local.service_accounts : idx => sa
    if sa["create"]
  }

  project      = format("%s", var.project)
  account_id   = each.value["account_id"]
  display_name = each.value["display_name"]
  description  = each.value["description"]

  depends_on = [
    google_project_service.api_services,
  ]
}

resource "google_project_iam_member" "iam_member_role" {
  for_each = {
    for idx, sa in local.sa_roles_flattened : "${sa["account_id"]}_${sa["role"]}" => sa
  }

  project = var.project
  role    = replace(each.value["role"], "{{PROJECT_ID}}", var.project)
  member  = "serviceAccount:${each.value["account_id"]}@${var.project}.iam.gserviceaccount.com"

  depends_on = [
    google_service_account.service_account,
  ]
}

# Step 3: Create a VPC
resource "google_compute_network" "vpc_network" {
  name                    = "${var.organization}-vpc"
  auto_create_subnetworks = false

  depends_on = [
    google_project_service.api_services
  ]
}

# Step 4: Create Cloud Router
resource "google_compute_router" "router" {
  project = var.project
  name    = "${var.organization}-router"
  network = google_compute_network.vpc_network.id
  region  = var.region

  depends_on = [
    google_compute_network.vpc_network
  ]
}

# Step 5: Create Nat Gateway
resource "google_compute_router_nat" "nat" {
  name                               = "${var.organization}-nat-router"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }

  depends_on = [
    google_compute_router.router
  ]
}

# Step 6: Create subnetworks
resource "google_compute_subnetwork" "subnetwork" {
  for_each = {
    for k, v in var.subnetwork_map : k => v
  }

  name          = each.value["name"]
  ip_cidr_range = each.value["cidr"]
  region        = var.region
  network       = google_compute_network.vpc_network.id
  secondary_ip_range = [
    for i in range(
      length(
        contains(
        keys(var.secondary_ranges), each.value.name) == true
        ? var.secondary_ranges[each.value.name]
        : []
    )) :
    var.secondary_ranges[each.value.name][i]
  ]

  depends_on = [
    google_compute_network.vpc_network,
  ]
}

# Step 7: Create firewall rules
resource "google_compute_firewall" "rules" {
  for_each = {
    for k, v in var.firewall_rules : k => v
  }

  project     = var.project
  name        = each.value["name"]
  network     = google_compute_network.vpc_network.name
  description = each.value["description"]

  allow {
    protocol = each.value["protocol"]
    ports    = lookup(each.value, "ports", null)
  }

  source_ranges = try(each.value.source_ip_ranges, [])

  depends_on = [
    google_compute_network.vpc_network
  ]
}

# Step 8: Create secrets
resource "random_password" "password" {
  for_each = {
    for k, v in var.secrets_map : k => v
  }

  length           = each.value["chars_count"]
  special          = each.value["use_special_charts"]
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Step 9: Populate secrets
resource "google_secret_manager_secret" "secret" {
  for_each = {
    for k, v in var.secrets_map : k => v
  }

  secret_id = each.value["secret_id"]

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  depends_on = [
    random_password.password
  ]
}

resource "google_secret_manager_secret_version" "secret_version" {
  for_each = {
    for k, v in var.secrets_map : k => v
    if v.secret_id != "django-settings"
  }

  secret      = google_secret_manager_secret.secret[each.key].id
  secret_data = random_password.password[each.key].result
}

resource "google_secret_manager_secret_version" "django_settings" {
  secret = google_secret_manager_secret.secret["django"].id
  secret_data = templatefile("files/env.tpl", {
    secret_key = random_password.password["django"].result
    user       = var.postgres_settings.user
    password   = random_password.password["postgres"].result
    ip_addr    = var.postgres_settings.ip_addr
    port       = var.postgres_settings.port
    name       = var.postgres_settings.name
    level      = var.django_settings.level
    env        = terraform.workspace
  })

  depends_on = [
    random_password.password,
    google_secret_manager_secret.secret,
  ]
}

resource "google_secret_manager_secret_iam_binding" "django_settings" {
  secret_id = google_secret_manager_secret.secret["django"].id
  role      = "roles/secretmanager.secretAccessor"
  members   = ["serviceAccount:${google_service_account.service_account["django"].email}"]

  depends_on = [
    google_service_account.service_account["django"],
  ]
}

# Step 10: Deploy PostgreSQL instance
resource "google_compute_address" "postgres_internal" {
  count        = var.postgres_settings.create ? 1 : 0
  name         = "postgres-internal-ip"
  subnetwork   = google_compute_subnetwork.subnetwork["sql"].id
  address_type = "INTERNAL"
  address      = var.postgres_settings.ip_addr
  region       = var.region
}

resource "google_compute_instance" "postgres" {
  count                     = var.postgres_settings.create ? 1 : 0
  name                      = "${var.service}-db"
  machine_type              = var.postgres_settings.type
  zone                      = "${var.region}-a"
  allow_stopping_for_update = true

  boot_disk {
    auto_delete = true
    device_name = "${var.service}-db"
    initialize_params {
      image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
    }
  }

  network_interface {
    network    = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.subnetwork["sql"].id
    network_ip = google_compute_address.postgres_internal[count.index].address
    access_config {
    }
  }

  can_ip_forward      = false
  deletion_protection = false
  enable_display      = false

  labels = {
    goog-ec-src = "vm_add-tf"
    env         = terraform.workspace
    app         = "postgres"
  }

  metadata = {
    enable-oslogin = false
    ssh-keys       = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
    startup-script = <<-EOF
      #! /bin/bash
      set -euo pipefail

      sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
      curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg

      export DEBIAN_FRONTEND=noninteractive
      apt update
      apt install -y postgresql-16
      apt autoremove -y
      sed -i -e"s/^#listen_addresses =.*$/listen_addresses = '*'/" /etc/postgresql/16/main/postgresql.conf
      sed -i -e"s/^max_connections = 100.*$/max_connections = 1000/" /etc/postgresql/16/main/postgresql.conf
      sed -i '/^host/s/ident/md5/' /etc/postgresql/16/main/pg_hba.conf
      sed -i '/^local/s/peer/trust/' /etc/postgresql/16/main/pg_hba.conf
      echo "host all all 0.0.0.0/0 md5" | sudo tee -a /etc/postgresql/16/main/pg_hba.conf
      systemctl restart postgresql
      systemctl enable postgresql
      sudo -u postgres psql -c "CREATE DATABASE ${var.postgres_settings.user};"
      sudo -u postgres psql -c "CREATE USER ${var.postgres_settings.user} WITH PASSWORD '${random_password.password["postgres"].result}';"
      sudo -u postgres psql -c "ALTER ROLE ${var.postgres_settings.user} SET client_encoding TO 'utf8';"
      sudo -u postgres psql -c "ALTER ROLE ${var.postgres_settings.user} SET default_transaction_isolation TO 'read committed';"
      sudo -u postgres psql -c "ALTER ROLE ${var.postgres_settings.user} SET timezone TO 'UTC';"
      sudo -u postgres psql -c "ALTER DATABASE ${var.postgres_settings.user} OWNER TO ${var.postgres_settings.user};"
      ufw allow 5432/tcp
    EOF
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
    provisioning_model  = "STANDARD"
  }

  service_account {
    email = google_service_account.service_account["django"].email
    scopes = [
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/trace.append",
    ]
  }

  shielded_instance_config {
    enable_integrity_monitoring = true
    enable_secure_boot          = false
    enable_vtpm                 = true
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    google_compute_subnetwork.subnetwork["sql"],
    random_password.password,
  ]
}
