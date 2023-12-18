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

1. Build `traffic-detection` image using Cloud Build:

   ```
   cd apps/traffic-detection/
   gcloud builds submit --tag gcr.io/$PROJECT_ID/traffic-detection:<version> .
   ```

Build:
- `apps/traffic-detection/`
  - `Dockerfile`: the Docker file with instructions to assemble the image
  - `cloudbuild.yaml`: the YAML file with the steps and settings of building and pushing the Docker image into Cloud container registry
  - `server.py`: the Python script to run the traffic-detection 

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
  - `gpu_hpa.tf`: the YAML file to enable autoscaling based on GPU usage
- `iac/files/`
  - `service_accounts.json`: the JSON file to add roles to Terraform service account
