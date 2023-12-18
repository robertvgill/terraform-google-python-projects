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

## Local development

After deploying elements:

1. TODO get settings file locally.
1. Setup Python environment and install dependencies
   ```
   virtualenv venv
   source venv/bin/activate
   pip install -r requirements.txt
   ```

## Files

Django website source

- `manage.py`, `ribc/`, `requirements.txt`
  - Generated from `django-admin startproject` command

Manual edits:

- `ribc/settings.py` updated to use `django-environ` and `django-storages`, pull secret settings
- Custom migration in `ribc/migrations` to create superuser programatically as a data migration
- Basic models, views, and templates added.
- App presumes data entry from admin, displayed on website.

Deployment:

- `main.tf`
  - one file for all Terraform config
- `files/`
  - `env.tpl`: template file to help create the django settings file
  - `gunicorn.service`: the Service file Gunicorn
  - `gunicorn.socket`: the Socket file Gunicorn
  - `ribcwebsite.nginx`: the Nginx file to Proxy Pass to Gunicorn
  - `service_accounts.json`: the JSON file to add roles to Django service account
  - `ops-agent-postgresql.yaml`: the YAML file to configure Ops Agent for PostgreSQL instance
