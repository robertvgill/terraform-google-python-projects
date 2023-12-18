region       = "asia-southeast1"
service      = "django"
organization = "ribc"
fqdn         = "ribc.com.sg"

subnetwork_map = {
  "web" = {
    name = "web"
    cidr = "10.10.10.0/24"
  }
  "sql" = {
    name = "sql"
    cidr = "10.10.20.0/24"
  }
}

secondary_ranges = {
  web = [
    {
      range_name    = "web-secondary"
      ip_cidr_range = "192.168.10.0/24"
    },
  ]
  sql = [
    {
      range_name    = "sql-secondary"
      ip_cidr_range = "192.168.20.0/24"
    },
  ]
}

firewall_rules = {
  "allow-ssh" = {
    name        = "allow-ssh"
    protocol    = "tcp"
    ports       = ["22"]
    priority    = null
    description = "Allow SSH"
    source_ip_ranges = [
      "198.51.100.32/27",
    ]
  },
  "allow-http" = {
    name        = "allow-http"
    protocol    = "tcp"
    ports       = ["80"]
    priority    = null
    tags        = ["http"]
    description = "Allow HTTP"
    source_ip_ranges = [
      "0.0.0.0/0",
    ]
  },
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
      "10.10.10.0/24",
      "192.168.10.0/24",
    ]
  },
  "allow-health-checks" = {
    name        = "allow-health-checks"
    protocol    = "tcp"
    ports       = ["8000"]
    priority    = null
    description = "Allow Health Checks"
    source_ip_ranges = [
      "35.191.0.0/16",
      "130.211.0.0/22",
    ]
  },
}

secrets_map = {
  django = {
    secret_id          = "django-settings"
    chars_count        = 50
    use_special_charts = true
  }

  postgres = {
    secret_id          = "postgres-password"
    chars_count        = 32
    use_special_charts = false
  }

  superuser = {
    secret_id          = "superuser-password"
    chars_count        = 32
    use_special_charts = true
  }
}

postgres_settings = {
  create  = true
  name    = "ribc"
  type    = "e2-medium"
  ip_addr = "10.10.20.4"
  port    = "5432"
  user    = "ribc"
}

django_settings = {
  type  = "e2-small"
  min   = 1
  max   = 5
  cpu   = 0.5
  level = "DEBUG"
}
