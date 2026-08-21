terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_project_service" "apis" {
  for_each = toset([
    "storage.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
  ])
  service            = each.value
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# GCS bucket (DVC remote + model artifacts)
# ---------------------------------------------------------------------------
resource "google_storage_bucket" "mlops" {
  name                        = var.bucket_name
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true

  depends_on = [google_project_service.apis]
}

# ---------------------------------------------------------------------------
# Service account: least-privilege, objectAdmin scoped to this bucket only
# ---------------------------------------------------------------------------
resource "google_service_account" "mlops_sa" {
  account_id   = "mlops-lab-sa"
  display_name = "MLOps Lab SA"

  depends_on = [google_project_service.apis]
}

resource "google_storage_bucket_iam_member" "sa_object_admin" {
  bucket = google_storage_bucket.mlops.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.mlops_sa.email}"
}

# ---------------------------------------------------------------------------
# Workload Identity Federation: lets GitHub Actions impersonate mlops_sa
# without ever creating a downloadable JSON key (blocked by org policy).
# ---------------------------------------------------------------------------
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-pool"
  display_name              = "GitHub Actions Pool"

  depends_on = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub Provider"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }

  # Restrict to this exact repo only.
  attribute_condition = "assertion.repository == \"${var.github_repo}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "wif_impersonation" {
  service_account_id = google_service_account.mlops_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}

# dvc[gs] (gcsfs cu) khong xu ly dung credential kieu external_account co
# impersonation - gay loi "Gaia id not found". Nen cho WIF principal quyen
# truc tiep tren bucket, GitHub Actions dung token federated thang, khong
# impersonate SA nua (auth step trong mlops.yml bo input service_account).
resource "google_storage_bucket_iam_member" "wif_object_admin" {
  bucket = google_storage_bucket.mlops.name
  role   = "roles/storage.objectAdmin"
  member = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}

# ---------------------------------------------------------------------------
# VM for serving (FastAPI on :8000)
# ---------------------------------------------------------------------------
resource "google_compute_firewall" "allow_mlops_serve" {
  name    = "allow-mlops-serve"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["8000"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["mlops-serve"]
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-mlops-ssh"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["mlops-serve"]
}

resource "google_compute_instance" "mlops_serve" {
  name         = "mlops-serve"
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["mlops-serve"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
    }
  }

  network_interface {
    network = "default"
    access_config {} # ephemeral public IP
  }

  service_account {
    email  = google_service_account.mlops_sa.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    ssh-keys = "${var.vm_user}:${var.ssh_public_key}"
  }
}
