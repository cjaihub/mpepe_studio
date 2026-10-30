# ─── Pub/Sub Priority Queue System ──────────────────────────────────────────

# Dead Letter Topic for poison-pill GPU jobs
resource "google_pubsub_topic" "compute_jobs_dead_letter" {
  project = var.project_id
  name    = "compute-jobs-dead-letter-${var.environment}"

  labels = {
    environment = var.environment
    system      = "looks-compute"
  }

  depends_on = [google_project_service.required_services]
}

# Priority Lanes: biz (highest), pro, free (lowest)
resource "google_pubsub_topic" "compute_jobs_biz" {
  project = var.project_id
  name    = "compute-jobs-biz-${var.environment}"

  labels = {
    environment = var.environment
    lane        = "biz"
    system      = "looks-compute"
  }

  depends_on = [google_project_service.required_services]
}

resource "google_pubsub_topic" "compute_jobs_pro" {
  project = var.project_id
  name    = "compute-jobs-pro-${var.environment}"

  labels = {
    environment = var.environment
    lane        = "pro"
    system      = "looks-compute"
  }

  depends_on = [google_project_service.required_services]
}

resource "google_pubsub_topic" "compute_jobs_free" {
  project = var.project_id
  name    = "compute-jobs-free-${var.environment}"

  labels = {
    environment = var.environment
    lane        = "free"
    system      = "looks-compute"
  }

  depends_on = [google_project_service.required_services]
}

# ─── Subscriptions for Batch Consumers (GKE Spot GPU Workers) ───────────────

resource "google_pubsub_subscription" "batch_worker_biz" {
  project              = var.project_id
  name                 = "sub-batch-worker-biz-${var.environment}"
  topic                = google_pubsub_topic.compute_jobs_biz.id
  ack_deadline_seconds = 600

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.compute_jobs_dead_letter.id
    max_delivery_attempts = 5
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }
}

resource "google_pubsub_subscription" "batch_worker_pro" {
  project              = var.project_id
  name                 = "sub-batch-worker-pro-${var.environment}"
  topic                = google_pubsub_topic.compute_jobs_pro.id
  ack_deadline_seconds = 600

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.compute_jobs_dead_letter.id
    max_delivery_attempts = 5
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }
}

resource "google_pubsub_subscription" "batch_worker_free" {
  project              = var.project_id
  name                 = "sub-batch-worker-free-${var.environment}"
  topic                = google_pubsub_topic.compute_jobs_free.id
  ack_deadline_seconds = 600

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.compute_jobs_dead_letter.id
    max_delivery_attempts = 3
  }

  retry_policy {
    minimum_backoff = "15s"
    maximum_backoff = "600s"
  }
}

# ─── Cloud Billing Budget Alerts Pub/Sub Topic ───────────────────────────────

resource "google_pubsub_topic" "billing_budget_alerts" {
  project = var.project_id
  name    = "billing-budget-alerts"

  labels = {
    system = "budget-guard"
  }

  depends_on = [google_project_service.required_services]
}
