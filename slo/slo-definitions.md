# SLO Definitions

## Service: observability-demo

---

### SLO 1 — Availability

**SLI definition:** Ratio of successful HTTP requests (non-5xx) over total requests

**PromQL expression:**
1 - (
sum(rate(http_requests_total{status=~"5.."}[5m]))
/
sum(rate(http_requests_total[5m]))
)

**SLO target:** 99.5% over a rolling 30-day window

**Reasoning:** 99.5% allows 216 minutes of downtime per month. This is appropriate for an internal service where occasional brief outages are acceptable, but reliability is still expected. A stricter SLO like 99.9% would leave only 43 minutes of budget — too tight for a small team without dedicated on-call rotation.

**Error budget calculation:**
- Error budget = (1 - 0.995) x 30 days x 24 hours x 60 minutes
- Error budget = 0.005 x 43200 minutes
- Error budget = 216 minutes per 30-day window

---

### SLO 2 — Latency

**SLI definition:** Ratio of requests completing under 500ms

**PromQL expression:**
sum(rate(http_request_duration_seconds_bucket{le="0.5"}[5m]))
/
sum(rate(http_request_duration_seconds_count[5m]))

**SLO target:** 95% of requests under 500ms

**Reasoning:** 500ms is the threshold where users consciously perceive slowness. Targeting the 95th percentile allows for occasional slow requests caused by garbage collection, cold starts, or transient load spikes without violating the SLO on normal traffic.

**Error budget:** 5% of requests may exceed 500ms

---

### SLO 3 — Error Rate

**SLI definition:** Ratio of non-error requests

**PromQL expression:**
sum(rate(http_requests_total{status!~"5.."}[5m]))
/
sum(rate(http_requests_total[5m]))

**SLO target:** 99% of requests succeed

**Reasoning:** 1% error rate is the baseline industry standard for internal services. This leaves room for expected transient errors while enforcing that the service is fundamentally reliable.

---

### SLO 4 — Saturation (CPU)

**SLI definition:** CPU utilisation below threshold

**PromQL expression:**
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

**SLO target:** CPU below 80% for 95% of the time over a rolling 24-hour window

**Reasoning:** Sustained CPU above 80% indicates the service is approaching saturation and will degrade under additional load. Keeping below 80% ensures headroom for traffic spikes.

---

## Error Budget Policy

### At 50% budget consumed
- Review all recent deployments for regressions
- Freeze non-critical feature work
- Assign one engineer to investigate and monitor the burn rate

### At 75% budget consumed
- All non-reliability work paused immediately
- Engineering lead notified
- Daily error budget review until budget recovers

### At 100% budget consumed
- Full feature freeze — no new deployments except reliability fixes
- Mandatory reliability sprint begins
- Post-incident review required before resuming feature work
- SLO target reviewed — is it realistic given current capacity?

### Decision ownership
The engineering lead owns the decision to freeze features. The on-call engineer owns the incident response. SLOs are reviewed monthly by the full engineering team.

### Review cadence
SLOs reviewed monthly. Targets adjusted based on:
- User feedback and business requirements
- Historical error budget consumption
- Team capacity and growth
