terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.30.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.30.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# ─── Required API Services ───────────────────────────────────────────────────

resource "google_project_service" "required_services" {
  for_each = toset([
    "run.googleapis.com",
    "pubsub.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbilling.googleapis.com",
    "billingbudgets.googleapis.com",
    "bigquery.googleapis.com",
    "firestore.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
  ])

  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

# ─── Artifact Registry for GPU Container Images ──────────────────────────────

resource "google_artifact_registry_repository" "looks_containers" {
  provider      = google-beta
  project       = var.project_id
  location      = var.region
  repository_id = "oneova-looks-${var.environment}"
  description   = "Docker container images for Cloud Run GPU & GKE batch workers"
  format        = "DOCKER"

  depends_on = [google_project_service.required_services]
}
