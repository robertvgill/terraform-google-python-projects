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
   gcloud services enable cloudresourcemanager.googleapis.com
   ```

1. Apply Terraform

   ```
   terraform init -reconfigure -upgrade
   terraform plan -var project=$PROJECT_ID
   terraform apply -var project=$PROJECT_ID -auto-approve
   ```

Deployment:

- `main.tf`
  - one file for all Terraform config
- `files/`
  - `env.tpl`: template file to help create the django settings file
  - `service_accounts.json`: the JSON file to add roles to Django service account
