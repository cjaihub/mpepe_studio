output "pubsub_compute_biz_topic" {
  description = "Pub/Sub Topic for Biz Priority Lane"
  value       = google_pubsub_topic.compute_jobs_biz.id
}

output "pubsub_compute_pro_topic" {
  description = "Pub/Sub Topic for Pro Priority Lane"
  value       = google_pubsub_topic.compute_jobs_pro.id
}

output "pubsub_compute_free_topic" {
  description = "Pub/Sub Topic for Free Priority Lane"
  value       = google_pubsub_topic.compute_jobs_free.id
}

output "pubsub_budget_alerts_topic" {
  description = "Pub/Sub Topic for Cloud Billing Budget Alerts"
  value       = google_pubsub_topic.billing_budget_alerts.id
}

output "cloud_run_gpu_service_name" {
  description = "Cloud Run GPU service name"
  value       = google_cloud_run_v2_service.gpu_interactive_service.name
}

output "gke_batch_cluster_name" {
  description = "GKE Autopilot cluster name for batch GPU workers"
  value       = google_container_cluster.batch_compute_cluster.name
}

output "bigquery_dataset_id" {
  description = "BigQuery dataset ID for Looks analytics"
  value       = google_bigquery_dataset.looks_analytics.dataset_id
}
