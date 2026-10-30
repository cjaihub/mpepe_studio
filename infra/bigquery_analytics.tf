# ─── BigQuery Analytics Dataset & Partitioned Tables ─────────────────────────
# Offloads telemetry and AI feedback from Firestore to BigQuery for cost-efficient analytics.

resource "google_bigquery_dataset" "looks_analytics" {
  project                    = var.project_id
  dataset_id                 = "looks_analytics"
  friendly_name              = "Oneova Looks Analytics & Learning Signals"
  description                = "Analytics dataset storing user feedback, look events, and GPU compute performance"
  location                   = var.region
  delete_contents_on_destroy = false

  labels = {
    environment = var.environment
    system      = "looks-analytics"
  }

  depends_on = [google_project_service.required_services]
}

# 1. AI Skill Feedback Table (Powers self-learning loop §8.4)
resource "google_bigquery_table" "ai_skill_feedback" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.looks_analytics.dataset_id
  table_id   = "ai_skill_feedback"

  time_partitioning {
    type  = "DAY"
    field = "createdAt"
  }

  clustering = ["skillId", "skillVersion", "accepted"]

  schema = jsonencode([
    { name = "id", type = "STRING", mode = "REQUIRED" },
    { name = "userId", type = "STRING", mode = "REQUIRED" },
    { name = "skillId", type = "STRING", mode = "REQUIRED" },
    { name = "skillVersion", type = "STRING", mode = "REQUIRED" },
    { name = "action", type = "STRING", mode = "NULLABLE" },
    { name = "accepted", type = "BOOLEAN", mode = "REQUIRED" },
    { name = "userAdjustmentsJson", type = "STRING", mode = "NULLABLE" },
    { name = "undoOccurred", type = "BOOLEAN", mode = "NULLABLE" },
    { name = "latencyMs", type = "INTEGER", mode = "NULLABLE" },
    { name = "createdAt", type = "TIMESTAMP", mode = "REQUIRED" },
  ])
}

# 2. Look Events Table
resource "google_bigquery_table" "look_events" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.looks_analytics.dataset_id
  table_id   = "look_events"

  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }

  clustering = ["lookId", "eventType", "platform"]

  schema = jsonencode([
    { name = "eventId", type = "STRING", mode = "REQUIRED" },
    { name = "lookId", type = "STRING", mode = "REQUIRED" },
    { name = "userId", type = "STRING", mode = "REQUIRED" },
    { name = "eventType", type = "STRING", mode = "REQUIRED" },
    { name = "platform", type = "STRING", mode = "NULLABLE" },
    { name = "timestamp", type = "TIMESTAMP", mode = "REQUIRED" },
  ])
}

# 3. Compute Job Metrics Table
resource "google_bigquery_table" "compute_job_metrics" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.looks_analytics.dataset_id
  table_id   = "compute_job_metrics"

  time_partitioning {
    type  = "DAY"
    field = "completedAt"
  }

  clustering = ["taskType", "priorityLane", "status"]

  schema = jsonencode([
    { name = "jobId", type = "STRING", mode = "REQUIRED" },
    { name = "userId", type = "STRING", mode = "REQUIRED" },
    { name = "taskType", type = "STRING", mode = "REQUIRED" },
    { name = "priorityLane", type = "STRING", mode = "REQUIRED" },
    { name = "durationMs", type = "INTEGER", mode = "NULLABLE" },
    { name = "status", type = "STRING", mode = "REQUIRED" },
    { name = "retryCount", type = "INTEGER", mode = "NULLABLE" },
    { name = "workerId", type = "STRING", mode = "NULLABLE" },
    { name = "completedAt", type = "TIMESTAMP", mode = "REQUIRED" },
  ])
}
