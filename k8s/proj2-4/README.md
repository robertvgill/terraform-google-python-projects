## Provisioning, Migrations, and Deployment

1. Create project with billing enabled, and configure gcloud for that project

   ```
   PROJECT_ID=your-project-id
   gcloud config set project $PROJECT_ID
   ```

1. Configure default credentials (allows Terraform to apply changes):

   ```
   gcloud auth application-default login
   ```

1. Enable base services:

   ```
   gcloud services enable cloudbuild.googleapis.com cloudresourcemanager.googleapis.com
   ```

1. Build `ribc-pg-backup` image using Cloud Build:

   ```
   cd apps/ribc-pg-backup/
   gcloud builds submit --tag gcr.io/$PROJECT_ID/ribc-pg-backup:1.0 .
   ```

1. Build `ribc-scheduler` image using Cloud Build:

   ```
   cd apps/ribc-scheduler/
   gcloud builds submit --tag gcr.io/$PROJECT_ID/ribc-scheduler:<version> .
   ```

Build:
- `apps/ribc-pg-backup/`
  - `Dockerfile`: the Docker file with instructions to assemble the image
  - `cloudbuild.yaml`: the YAML file with the steps and settings of building and pushing the Docker image into Cloud container registry
  - `snapshot.py`: the Python script to backup persistent volumen claim for PostgreSQL instance  

- `apps/ribc-schedule/`
  - `Dockerfile`: the Docker file with instructions to assemble the image
  - `cloudbuild.yaml`: the YAML file with the steps and settings of building and pushing the Docker image into Cloud container registry
  - `schedule.py`: the Python script to run the ribc-scheduler  

1. Apply Terraform

   ```
   iac/
   terraform init -reconfigure -upgrade
   terraform plan -var project=$PROJECT_ID
   terraform apply -var project=$PROJECT_ID -auto-approve
   ```

Deployment:
- `iac/`
  - `main.tf`: the YAML file for all prerequisites resources
  - `postgresql.tf`: the YAML file for all PostgreSQL configurations
- `iac/files/`
  - `service_accounts.json`: the JSON file to add roles to Terraform service account
