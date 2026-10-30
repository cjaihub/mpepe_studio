# ─── Cloud Billing Budget & Spend Alert Policies ─────────────────────────────
# Automatically notifies Pub/Sub when spend crosses Amber (80%) and Red (100%) thresholds.

resource "google_billing_budget" "monthly_spend_budget" {
  count = var.billing_account_id != "" ? 1 : 0

  billing_account = var.billing_account_id
  display_name    = "Oneova Looks Cloud Spend Budget (${var.environment})"

  budget_filter {
    projects = ["projects/${var.project_id}"]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.monthly_budget_amount_usd)
    }
  }

  # Amber threshold (default 80%)
  threshold_rules {
    threshold_percent = var.amber_threshold_ratio
    spend_basis       = "CURRENT_SPEND"
  }

  # Red threshold (default 100%)
  threshold_rules {
    threshold_percent = var.red_threshold_ratio
    spend_basis       = "CURRENT_SPEND"
  }

  all_updates_rule {
    pubsub_topic                     = google_pubsub_topic.billing_budget_alerts.id
    schema_version                   = "1.0"
    monitoring_notification_channels = []
    disable_default_iam_recipients   = false
  }

  depends_on = [
    google_pubsub_topic.billing_budget_alerts,
    google_project_service.required_services,
  ]
}
