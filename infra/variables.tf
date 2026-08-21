variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "bucket_name" {
  type        = string
  description = "Globally unique GCS bucket name (data + model artifacts)"
}

variable "machine_type" {
  type    = string
  default = "e2-small"
}

variable "vm_user" {
  type        = string
  description = "Linux username to create on the VM (used for SSH)"
}

variable "ssh_public_key" {
  type        = string
  description = "Contents of the public key (e.g. ~/.ssh/mlops_deploy.pub) for GitHub Actions to SSH in"
}

variable "github_repo" {
  type        = string
  description = "GitHub repo allowed to impersonate the service account via WIF, format 'owner/repo'"
}
