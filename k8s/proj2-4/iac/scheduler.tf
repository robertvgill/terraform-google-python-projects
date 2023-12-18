# Step 22: Create Kubernetes namespace
resource "kubernetes_namespace" "scheduler" {
  count = var.cluster_settings.create && var.scheduler_settings.create ? 1 : 0

  metadata {
    annotations = {
      "scheduler.alpha.kubernetes.io/node-selector" : "agentpool=scheduler-pool"
    }

    name = var.scheduler_settings.namespace
  }

  depends_on = [
    google_container_node_pool.pools,
  ]
}

# Step 23: Create Kubernetes service account
resource "kubernetes_service_account" "scheduler" {
  count = var.cluster_settings.create && var.scheduler_settings.create ? 1 : 0

  metadata {
    name      = "scheduler"
    namespace = kubernetes_namespace.scheduler[0].metadata[0].name
  }

  depends_on = [
    kubernetes_namespace.scheduler,
  ]
}

# Step 24: Create Kubernetes secret for database connection information
resource "kubernetes_secret" "scheduler" {
  count = var.cluster_settings.create && var.scheduler_settings.create ? 1 : 0

  metadata {
    name      = "pgconninfo"
    namespace = kubernetes_namespace.scheduler[0].metadata[0].name
  }

  data = {
    pgconninfo = base64encode(var.scheduler_settings.pgconninfo)
  }
}

# Step 25: Populate secret in Secret Manager
resource "google_secret_manager_secret" "scheduler" {
  count = var.cluster_settings.create && var.scheduler_settings.create ? 1 : 0

  secret_id = "scheduler-${kubernetes_secret.scheduler[0].metadata[0].name}"

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  depends_on = [
    kubernetes_secret.scheduler,
  ]
}

resource "google_secret_manager_secret_version" "scheduler" {
  count = var.cluster_settings.create && var.scheduler_settings.create ? 1 : 0

  secret      = google_secret_manager_secret.scheduler[0].id
  secret_data = var.scheduler_settings.pgconninfo

  depends_on = [
    google_secret_manager_secret.scheduler,
  ]
}

# Step 26: Create Kubernetes cronjob
resource "kubernetes_cron_job_v1" "scheduler" {
  count = var.cluster_settings.create && var.scheduler_settings.create ? 1 : 0

  metadata {
    name      = var.scheduler_settings.name
    namespace = kubernetes_namespace.scheduler[0].metadata[0].name
  }

  spec {
    schedule = var.scheduler_settings.cronjob_schedule

    job_template {
      metadata {
        name = var.scheduler_settings.name
      }

      spec {
        template {
          metadata {
            name = var.scheduler_settings.name
          }

          spec {
            container {
              name  = "scheduler-container"
              image = "gcr.io/${var.project}/${var.scheduler_settings.image}:${var.scheduler_settings.version}"

              env {
                name  = "INPUT_FOLDER"
                value = var.scheduler_settings.input_folder
              }

              env {
                name  = "OUTPUT_FOLDER"
                value = var.scheduler_settings.output_folder
              }

              env {
                name = "PGCONNINFO"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.scheduler[0].metadata[0].name
                    key  = "pgconninfo"
                  }
                }
              }

              command = [
                "/bin/sh",
                "-c",
                "bash copy_inputs.sh -i ${var.scheduler_settings.input_folder} && python schedule.py && bash copy_outputs.sh -o ${var.scheduler_settings.output_folder} -d ftp://ribc.com.sg/schedule",
              ]
            }

            restart_policy = "OnFailure"
          }
        }
      }
    }
  }
}