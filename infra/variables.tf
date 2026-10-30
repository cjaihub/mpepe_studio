variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "mpepe-2b4bd"
}

variable "region" {
  description = "Primary GCP region for compute and services"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Deployment environment (staging | production)"
  type        = string
  default     = "staging"
}

variable "billing_account_id" {
  description = "Cloud Billing Account ID for budget alerts (e.g. 012345-6789AB-CDEF01)"
  type        = string
  default     = ""
}

variable "monthly_budget_amount_usd" {
  description = "Target monthly budget ceiling in USD"
  type        = number
  default     = 500.0
}

variable "amber_threshold_ratio" {
  description = "Budget ratio triggering AMBER spend level (free-tier routed to on-device)"
  type        = number
  default     = 0.80
}

variable "red_threshold_ratio" {
  description = "Budget ratio triggering RED spend level (paid/critical cloud jobs only)"
  type        = number
  default     = 1.00
}

variable "cloud_run_gpu_max_instances" {
  description = "Maximum concurrent Cloud Run GPU (L4) instances"
  type        = number
  default     = 10
}

variable "gke_spot_gpu_max_nodes" {
  description = "Maximum GKE Autopilot Spot GPU nodes for batch rendering"
  type        = number
  default     = 20
}
