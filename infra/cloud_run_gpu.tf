# ─── Cloud Run GPU (L4) for Interactive Jobs ──────────────────────────────────
# Scales to zero to eliminate idle GPU costs; concurrency 1 for clean GPU pipeline allocation.

resource "google_cloud_run_v2_service" "gpu_interactive_service" {
  provider = google-beta
  project  = var.project_id
  name     = "oneova-gpu-interactive-${var.environment}"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_ONLY"

  template {
    scaling {
      min_instance_count = 0
      max_instance_count = var.cloud_run_gpu_max_instances
    }

    max_instance_request_concurrency = 1
    timeout                          = "300s"

    node_selector = {
      "run.googleapis.com/accelerator" = "nvidia-l4"
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/oneova-looks-${var.environment}/gpu-worker:latest"

      resources {
        limits = {
          cpu            = "4"
          memory         = "16Gi"
          "nvidia.com/gpu" = "1"
        }
      }

      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "CONCURRENCY"
        value = "1"
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  depends_on = [
    google_project_service.required_services,
    google_artifact_registry_repository.looks_containers,
  ]
}
