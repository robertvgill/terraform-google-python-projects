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
}
