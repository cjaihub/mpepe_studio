# ─── Firestore TTL Policies ──────────────────────────────────────────────────
# Automatically cleans up stale jobs, cached AI results, and rate-limit buckets
# without paying for delete queries or document scan operations.

# Note: Firestore TTL policies are enabled on the `expiresAt` timestamp field:
# 1. `computeJobs` -> expiresAt (72 hours after creation)
# 2. `aiResultCache` -> expiresAt (7 days after generation)
# 3. `rateLimits` -> expiresAt (24 hours after last hit)

# Using google_firestore_field resource to declare TTL policy
resource "google_firestore_field" "compute_jobs_ttl" {
  provider   = google-beta
  project    = var.project_id
  database   = "(default)"
  collection = "computeJobs"
  field      = "expiresAt"

  ttl_config {}

  depends_on = [google_project_service.required_services]
}

resource "google_firestore_field" "ai_result_cache_ttl" {
  provider   = google-beta
  project    = var.project_id
  database   = "(default)"
  collection = "aiResultCache"
  field      = "expiresAt"

  ttl_config {}

  depends_on = [google_project_service.required_services]
}

resource "google_firestore_field" "rate_limits_ttl" {
  provider   = google-beta
  project    = var.project_id
  database   = "(default)"
  collection = "rateLimits"
  field      = "expiresAt"

  ttl_config {}

  depends_on = [google_project_service.required_services]
}
