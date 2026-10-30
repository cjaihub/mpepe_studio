import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

// Custom metrics
const cacheHits = new Counter('ai_cache_hits');
const cacheMisses = new Counter('ai_cache_misses');
const rateLimitHits = new Counter('rate_limit_429');
const cachedLatency = new Trend('cached_latency_ms');
const uncachedLatency = new Trend('uncached_latency_ms');
const errorRate = new Rate('error_rate');

export const options = {
  scenarios: {
    // Spike test: rapidly scale to 10,000 RPS on staging endpoint
    ten_k_spike: {
      executor: 'ramping-arrival-rate',
      startRate: 100,
      timeUnit: '1s',
      preAllocatedVUs: 500,
      maxVUs: 2500,
      stages: [
        { duration: '30s', target: 1000 },   // Warm-up to 1,000 RPS
        { duration: '1m', target: 5000 },    // Scale to 5,000 RPS
        { duration: '30s', target: 10000 },  // Peak Spike: 10,000 RPS
        { duration: '1m', target: 10000 },   // Sustain 10,000 RPS
        { duration: '30s', target: 1000 },   // Cool-down
      ],
    },
  },
  thresholds: {
    // Cache hits must complete in <100ms p95
    cached_latency_ms: ['p(95)<100'],
    // Overall non-429 error rate must remain under 1%
    error_rate: ['rate<0.01'],
  },
};

const BASE_URL = __ENV.TARGET_URL || 'https://us-central1-mpepe-2b4bd.cloudfunctions.net/createLookOptimized';

// Common prompts designed to test cache clustering
const PROMPTS = [
  'Make it warmer and cinematic',
  'Lift shadows, lower contrast',
  'Teal and orange blockbuster look',
  'Moody vintage 90s film look',
  'Golden hour glow with soft highlights',
];

export default function () {
  const prompt = PROMPTS[Math.floor(Math.random() * PROMPTS.length)];
  const userId = `k6_user_${Math.floor(Math.random() * 1000)}`;

  const payload = JSON.stringify({
    data: {
      prompt: prompt,
      skillId: 'look_from_prompt',
      skillVersion: '1.0.0',
      imageStats: {
        meanLuminanceBin: 5,
        cctKelvinBin: 4500,
        tintBin: 0,
      },
    },
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
      'X-Firebase-AppCheck': 'k6-mock-valid-appcheck-token',
      'Authorization': `Bearer mock_token_for_${userId}`,
    },
    timeout: '5s',
  };

  const startTime = Date.now();
  const res = http.post(BASE_URL, payload, params);
  const latency = Date.now() - startTime;

  if (res.status === 200) {
    errorRate.add(0);
    const body = JSON.parse(res.body);

    if (body.result && body.result.cacheHit === true) {
      cacheHits.add(1);
      cachedLatency.add(latency);
    } else {
      cacheMisses.add(1);
      uncachedLatency.add(latency);
    }

    check(res, {
      'status is 200': (r) => r.status === 200,
      'has valid look data': () => body.result && body.result.data !== undefined,
    });
  } else if (res.status === 429) {
    // Rate limit hit as expected for burst users
    rateLimitHits.add(1);
    errorRate.add(0); // Expected token-bucket behavior, not a server crash
  } else {
    errorRate.add(1);
    check(res, {
      'unexpected failure': (r) => r.status < 500,
    });
  }

  sleep(0.01);
}
