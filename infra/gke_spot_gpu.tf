# ─── GKE Autopilot Cluster & Spot GPU Node Pool for Batch Jobs ───────────────
# Spot GPUs provide 60-90% cost savings over on-demand instances.
# In-flight jobs handle preemption signals (SIGTERM) gracefully and re-queue.

resource "google_container_cluster" "batch_compute_cluster" {
  provider = google-beta
  project  = var.project_id
  name     = "oneova-batch-cluster-${var.environment}"
  location = var.region

  # Enable Autopilot mode with workload-driven Spot GPU node provisioning
  enable_autopilot = true

  ip_allocation_policy {}

  vertical_pod_autoscaling {
    enabled = true
  }

  release_channel {
    channel = "REGULAR"
  }

  depends_on = [google_project_service.required_services]
}

# ─── Kubernetes Batch Consumer Deployment Spec (Spot GPU) ───────────────────
# Configured with 25s termination grace period to trap preemption and re-queue jobs.

locals {
  spot_worker_k8s_manifest = <<-EOT
apiVersion: apps/v1
kind: Deployment
metadata:
  name: oneova-spot-batch-worker
  namespace: default
  labels:
    app: spot-batch-worker
    tier: gpu-batch
spec:
  replicas: 2
  selector:
    matchLabels:
      app: spot-batch-worker
  template:
    metadata:
      labels:
        app: spot-batch-worker
    spec:
      terminationGracePeriodSeconds: 30
      nodeSelector:
        cloud.google.com/gke-spot: "true"
        cloud.google.com/gke-accelerator: "nvidia-l4"
      tolerations:
      - key: "cloud.google.com/gke-spot"
        operator: "Equal"
        value: "true"
        effect: "NoSchedule"
      - key: "nvidia.com/gpu"
        operator: "Exists"
        effect: "NoSchedule"
      containers:
      - name: gpu-batch-worker
        image: ${var.region}-docker.pkg.dev/${var.project_id}/oneova-looks-${var.environment}/gpu-worker:latest
        resources:
          limits:
            nvidia.com/gpu: "1"
            memory: "16Gi"
            cpu: "4"
          requests:
            nvidia.com/gpu: "1"
            memory: "8Gi"
            cpu: "2"
        env:
        - name: PROJECT_ID
          value: "${var.project_id}"
        - name: ENVIRONMENT
          value: "${var.environment}"
        - name: WORKER_TYPE
          value: "spot-batch"
  EOT
}
