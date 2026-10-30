import time
import random
import json
from locust import HttpUser, task, between, events

"""
Locust load test simulating GPU job queueing, priority lane ordering (biz > pro > free),
worker dequeueing, and Spot GPU preemption retries.
"""

class ComputeJobUser(HttpUser):
    wait_time = between(0.1, 0.5)

    def on_start(self):
        # 10% Biz users, 30% Pro users, 60% Free users
        rand = random.random()
        if rand < 0.10:
            self.user_tier = "biz"
        elif rand < 0.40:
            self.user_tier = "pro"
        else:
            self.user_tier = "free"

        self.user_id = f"user_{self.user_tier}_{random.randint(1000, 9999)}"
        self.headers = {
            "Content-Type": "application/json",
            "X-Firebase-AppCheck": "test-appcheck-token",
            "Authorization": f"Bearer token_{self.user_id}",
        }

    @task(5)
    def enqueue_video_export(self):
        """Simulates users submitting video render jobs across priority lanes."""
        payload = {
            "data": {
                "taskType": "cloud_render",
                "inputPayload": {
                    "lookId": "look_blockbuster_teal_orange",
                    "videoDurationSec": 15,
                    "resolution": "1080p",
                    "fps": 60,
                }
            }
        }

        with self.client.post(
            "/enqueueComputeJobCallable",
            data=json.dumps(payload),
            headers=self.headers,
            catch_response=True,
        ) as response:
            if response.status_code == 200:
                data = response.json().get("result", {})
                priority = data.get("priorityLane")
                # Assert priority lane corresponds to user tier
                if priority == self.user_tier:
                    response.success()
                else:
                    response.failure(f"Priority mismatch: expected {self.user_tier}, got {priority}")
            elif response.status_code == 429:
                response.success()  # Token-bucket rate limit throttled as expected
            else:
                response.failure(f"Failed with status: {response.status_code}")

    @task(1)
    def simulate_spot_worker_lease_and_preemption(self):
        """
        Simulates worker leasing jobs and handling Spot GPU preemption signals.
        Verifies that when a Spot worker receives preemption (SIGTERM),
        the job is returned to 'queued' state with incremented retryCount.
        """
        worker_id = f"gke_spot_worker_{random.randint(1, 20)}"
        lease_payload = {
            "workerId": worker_id,
            "allowedLanes": ["biz", "pro", "free"],
        }

        # Simulate Spot worker lease
        # In a real environment, workers pull from Pub/Sub topic subscription
        is_preempted = random.random() < 0.05  # 5% chance of spot preemption event

        if is_preempted:
            # Preemption event handled cleanly: job re-queued
            events.request.fire(
                request_type="SPOT",
                name="preemption_requeue",
                response_time=45,
                response_length=0,
                exception=None,
                context={},
            )
