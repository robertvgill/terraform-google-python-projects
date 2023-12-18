# Step 1: Activate service APIs
resource "google_project_service" "api_services" {
  project = var.project
  service = each.value
  for_each = toset([
    "cloudbuild.googleapis.com",         # Cloud Build API
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

# Step 11: Create Django instance
resource "google_compute_instance" "django" {

  name                      = "${var.service}-vm"
  machine_type              = var.django_settings.type
  zone                      = "${var.region}-a"
  allow_stopping_for_update = true

  boot_disk {
    auto_delete = true
    device_name = "${var.service}-vm"
    initialize_params {
      image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
    }
  }

  network_interface {
    network    = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.subnetwork["web"].id
    access_config {
    }
  }

  can_ip_forward      = false
  deletion_protection = false
  enable_display      = false

  labels = {
    goog-ec-src = "vm_add-tf"
    env         = terraform.workspace
    app         = var.service
  }

  metadata = {
    enable-oslogin = "FALSE"
    ssh-keys       = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
    startup-script = <<-EOF
      #! /bin/bash
      set -euo pipefail

      sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
      curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
      curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh

      export DEBIAN_FRONTEND=noninteractive
      apt update
      apt install -y nginx postgresql-client-16
      apt autoremove -y
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
      "https://www.googleapis.com/auth/cloud-platform",
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
    google_compute_subnetwork.subnetwork["web"],
  ]
}

# Step 12: Wait for startup completion 
resource "time_sleep" "startup_completion" {
  create_duration = "120s"

  depends_on = [
    google_compute_instance.django,
  ]
}

# Step 13: Configure Django instance
resource "null_resource" "configure_django" {
  connection {
    host        = google_compute_instance.django.network_interface[0].access_config[0].nat_ip
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("~/.ssh/id_rsa")
    agent       = false
  }

  provisioner "file" {
    source      = "${path.module}/files/gunicorn.socket"
    destination = "gunicorn.socket"
  }

  provisioner "local-exec" {
    command = <<-EOT
      sed -i -e"s/workers .*[0-9]/workers ${var.gunicorn_map.workers}/" ${path.module}/files/gunicorn.service
      sed -i -e"s/threads .*[0-9]/threads ${var.gunicorn_map.threads}/" ${path.module}/files/gunicorn.service
      sed -i -e"s/connections=.*[0-9]/connections=${var.gunicorn_map.connections}/" ${path.module}/files/gunicorn.service
    EOT
  }

  provisioner "file" {
    source      = "${path.module}/files/gunicorn.service"
    destination = "gunicorn.service"
  }

  provisioner "file" {
    source      = "${path.module}/files/website"
    destination = "website"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt install -y libpq-dev python3-pip",
      "sudo pip3 install -q google-auth google-cloud-logging google-cloud-secret-manager django django-environ gunicorn psycopg2-binary",
      "sudo mv /home/ubuntu/gunicorn.* /etc/systemd/system",
      "sudo mkdir -p /var/log/gunicorn",
      "sudo systemctl daemon-reload",
      "sudo systemctl start gunicorn.socket",
      "sudo systemctl enable gunicorn.socket",
      "sudo systemctl start gunicorn.service",
      "sudo systemctl enable gunicorn.service",
      "cd /home/ubuntu/website",
      "sudo python3 manage.py makemigrations",
      "sudo python3 manage.py migrate",
    ]
    on_failure = fail
  }

  provisioner "file" {
    source      = "${path.module}/files/ribcwebsite.nginx"
    destination = "ribcwebsite.nginx"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mv /home/ubuntu/ribcwebsite.nginx /etc/nginx/sites-available/ribcwebsite",
      "sudo ln -s /etc/nginx/sites-available/ribcwebsite /etc/nginx/sites-enabled",
      "sudo systemctl reload nginx",
      "sudo ufw allow 8000",
    ]
    on_failure = fail
  }

  depends_on = [
    google_compute_instance.postgres,
    google_secret_manager_secret_version.django_settings,
    time_sleep.startup_completion,
  ]
}

# Step 14: Create Django superuser
resource "null_resource" "create_superuser" {
  count = var.django_superuser.create ? 1 : 0

  connection {
    host        = google_compute_instance.django.network_interface[0].access_config[0].nat_ip
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("~/.ssh/id_rsa")
    agent       = false
  }

  provisioner "remote-exec" {
    inline = [
      "cd /home/ubuntu/website",
      "DJANGO_SUPERUSER_PASSWORD='${random_password.password["superuser"].result}'",
      "sudo python3 manage.py createsuperuser --username ${var.django_superuser.name} --email ${var.django_superuser.email} --noinput",
      "sudo python3 manage.py collectstatic",
      "sudo chown -R ubuntu:ubuntu staticfiles/"
    ]
    on_failure = fail
  }

  depends_on = [
    null_resource.configure_django,
  ]
}

# Step 15: Install Ops Agent
resource "null_resource" "ops_agent_db" {
  count = var.postgres_settings.create ? 1 : 0

  connection {
    host        = google_compute_instance.postgres[count.index].network_interface[0].access_config[0].nat_ip
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("~/.ssh/id_rsa")
    agent       = false
  }

  provisioner "file" {
    source      = "${path.module}/files/ops_agent_postgresql.yaml"
    destination = "config.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      "curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh",
      "sudo bash add-google-cloud-ops-agent-repo.sh --also-install",
      "sudo cp /etc/google-cloud-ops-agent/config.yaml /etc/google-cloud-ops-agent/config.yaml.bak",
      "sed -i -e's/username:.*$/username:${var.postgres_settings.user}/' config.yaml",
      "sed -i -e's/password:.*$/password:${random_password.password["postgres"].result}/' config.yaml",
      "sudo mv config.yaml /etc/google-cloud-ops-agent/config.yaml",
      "sudo systemctl restart google-cloud-ops-agent",
      "sleep 60",
      "rm -f add-google-cloud-ops-agent-repo.sh",
    ]
    on_failure = fail
  }

  depends_on = [
    null_resource.create_superuser,
  ]
}

resource "null_resource" "ops_agent_vm" {
  connection {
    host        = google_compute_instance.django.network_interface[0].access_config[0].nat_ip
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("~/.ssh/id_rsa")
    agent       = false
  }

  provisioner "remote-exec" {
    inline = [
      "curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh",
      "sudo bash add-google-cloud-ops-agent-repo.sh --also-install",
      "rm -f add-google-cloud-ops-agent-repo.sh",
    ]
    on_failure = fail
  }

  depends_on = [
    null_resource.create_superuser,
  ]
}

# Step 16: Shutdown Django instance
resource "null_resource" "shutdown_django" {
  provisioner "local-exec" {
    command = "gcloud -q compute instances stop --zone=${var.region}-a ${google_compute_instance.django.name}"
  }

  depends_on = [
    null_resource.ops_agent_vm,
  ]
}

# Step 17: Create a snapshot of Django instance
resource "google_compute_snapshot" "django" {
  project           = var.project
  name              = "${var.service}-snapshot"
  source_disk       = google_compute_instance.django.boot_disk[0].device_name
  zone              = "${var.region}-a"
  storage_locations = [var.region]

  depends_on = [
    null_resource.shutdown_django,
  ]
}

# Step 18: Create a disk image for Django template
resource "google_compute_image" "django" {
  project         = var.project
  name            = "${var.service}-latest"
  family          = var.service
  source_snapshot = google_compute_snapshot.django.self_link

  depends_on = [
    google_compute_snapshot.django,
  ]
}

# Step 19: Create an instance template
resource "google_compute_instance_template" "django" {
  project      = var.project
  name_prefix  = var.service
  machine_type = var.django_settings.type
  region       = var.region

  network_interface {
    network    = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.subnetwork["web"].id
  }

  disk {
    source_image = google_compute_image.django.self_link
    mode         = "READ_WRITE"
    type         = "PERSISTENT"
    auto_delete  = true
    boot         = true
  }

  can_ip_forward = false

  labels = {
    goog-ec-src = "vm_add-tf"
    env         = terraform.workspace
    app         = var.service
  }

  metadata = {
    enable-oslogin = "TRUE"
    startup-script = <<-EOF
      #! /bin/bash
      set -euo pipefail

      export DEBIAN_FRONTEND=noninteractive
      apt update
      apt upgrade -y
      apt full-upgrade -y
      apt dist-upgrade -y
      apt autoclean -y
      apt autoremove -y
      do-release-upgrade
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
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  shielded_instance_config {
    enable_integrity_monitoring = true
    enable_secure_boot          = false
    enable_vtpm                 = true
  }

  tags = [
    "allow-health-check",
  ]

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    google_compute_image.django,
  ]
}

# Step 20: Create health check
resource "google_compute_health_check" "django" {
  name                = "django-health-check"
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 10

  http_health_check {
    request_path = "/"
    port         = "8000"
  }
}

# Step 21: Create MIG
resource "google_compute_instance_group_manager" "django" {
  name               = "appserver-igm"
  zone               = "${var.region}-a"
  target_size        = var.django_settings.min
  base_instance_name = "${var.service}-mig"

  version {
    instance_template = google_compute_instance_template.django.self_link_unique
  }

  named_port {
    name = "customhttp"
    port = 8000
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.django.id
    initial_delay_sec = 300
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      target_size
    ]
  }

  depends_on = [
  ]
}

# Step 22: Create autoscaler
resource "google_compute_autoscaler" "django" {
  project = var.project
  name    = "${var.service}-autoscaler"
  zone    = "${var.region}-a"
  target  = google_compute_instance_group_manager.django.id

  autoscaling_policy {
    max_replicas    = var.django_settings.max
    min_replicas    = var.django_settings.min
    cooldown_period = 60

    cpu_utilization {
      target = var.django_settings.cpu
    }
  }

  depends_on = [
    google_compute_instance_group_manager.django,
  ]
}

# Step 23: Create backend service
resource "google_compute_backend_service" "django" {
  name                            = "${var.service}-backend-service"
  connection_draining_timeout_sec = 0
  health_checks                   = [google_compute_health_check.django.id]
  load_balancing_scheme           = "EXTERNAL_MANAGED"
  port_name                       = "customhttp"
  protocol                        = "HTTP"
  session_affinity                = "NONE"
  timeout_sec                     = 30

  backend {
    group           = google_compute_instance_group_manager.django.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0

  }

  depends_on = [
    google_compute_instance_group_manager.django,
  ]
}

# Step 24: Create external level 7 load balancer with MIG backend
# managed ssl certificate
resource "random_id" "certificate" {
  byte_length = 4
  prefix      = "${var.organization}-cert-"

  keepers = {
    domains = join(",", tolist([var.fqdn]))
  }
}

resource "google_compute_managed_ssl_certificate" "l7_managed_ssl_cert" {
  name = random_id.certificate.hex

  lifecycle {
    create_before_destroy = true
  }

  managed {
    domains = [var.fqdn]
  }

  depends_on = [
    google_project_service.api_services
  ]
}

# url maps
resource "google_compute_url_map" "l7_url_map" {

  name            = "${var.service}-url-map"
  default_service = google_compute_backend_service.django.id

  host_rule {
    hosts        = [var.fqdn]
    path_matcher = "allpaths"
  }

  path_matcher {
    name            = "allpaths"
    default_service = google_compute_backend_service.django.id

    path_rule {
      paths   = ["/*"]
      service = google_compute_backend_service.django.id
    }
  }
}

resource "google_compute_url_map" "l7_https_redirect_map" {
  name = "${var.service}-https-redirect"
  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

# http proxies
resource "google_compute_target_http_proxy" "l7_http_proxy" {
  name    = "${var.service}-target-http-proxy"
  url_map = join("", google_compute_url_map.l7_https_redirect_map.*.self_link)
}

resource "google_compute_target_https_proxy" "l7_https_proxy" {
  name             = "${var.service}-target-https-proxy"
  url_map          = google_compute_url_map.l7_url_map.id
  ssl_certificates = [google_compute_managed_ssl_certificate.l7_managed_ssl_cert.self_link]

  depends_on = [
    google_compute_managed_ssl_certificate.l7_managed_ssl_cert
  ]
}

resource "google_compute_global_address" "l7_public_ip" {
  name         = "${var.organization}-public-ip"
  ip_version   = "IPV4"
  address_type = "EXTERNAL"
}

# forwarding rules
resource "google_compute_global_forwarding_rule" "l7_http_forwarding_rule" {
  name                  = "${var.service}-http-forwarding-rule"
  ip_protocol           = "TCP"
  port_range            = "80"
  target                = google_compute_target_http_proxy.l7_http_proxy.id
  ip_address            = google_compute_global_address.l7_public_ip.id
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

resource "google_compute_global_forwarding_rule" "l7_https_forwarding_rule" {
  name                  = "${var.service}-https-forwarding-rule"
  ip_protocol           = "TCP"
  port_range            = "443"
  target                = google_compute_target_https_proxy.l7_https_proxy.id
  ip_address            = google_compute_global_address.l7_public_ip.id
  load_balancing_scheme = "EXTERNAL_MANAGED"
}
