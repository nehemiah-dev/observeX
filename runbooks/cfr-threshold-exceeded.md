# Runbook: CFR Threshold Exceeded

**Alerts:** `CFRThresholdExceeded` (critical), `CFRThresholdWarning` (warning)
**Severity:** critical / warning
**Dashboard:** http://localhost:3000/d/dora-metrics

---

## What is this alert?

**Change Failure Rate (CFR)** is the percentage of deployments to production that result in a failure, rollback, or hotfix. It is a DORA metric measuring pipeline quality and release confidence.

- `CFRThresholdWarning`: CFR has exceeded **5%** on a rolling 7-day window — approaching the SLO threshold
- `CFRThresholdExceeded`: CFR has exceeded **10%** on a rolling 7-day window — the SLO is breached. DORA classification is now Medium or Low
- `NoPipelineActivity`: No deployments have been recorded in 7 days — the pipeline may be stalled or the metric push step is broken

### DORA CFR benchmarks

| Classification | CFR |
|---|---|
| Elite | 0–5% |
| High | 5–10% |
| Medium | 10–15% |
| Low | >15% |

---

## Likely causes

- Tests are insufficient and bugs are reaching production
- The deployment process itself is fragile (infrastructure, secrets, network)
- Too many large changesets being merged without feature flags
- Insufficient staging or review environments
- Pushgateway metric incorrectly labelling successful deployments as failures

---

## Investigation steps

**Step 1 — Identify which deployments failed**

Open the [DORA dashboard](http://localhost:3000/d/dora-metrics). Look at the CFR time series and identify when failures began. Check GitHub Actions for recent failed or rolled-back runs.

```bash
# Query recent deployment results from Prometheus
curl -g 'http://localhost:9090/api/v1/query?query=github_actions_deployments_total'
```

**Step 2 — Classify failure type**

For each failed deployment, determine:
- Did the pipeline fail (build/test/deploy step)? → Fix the pipeline
- Did the deployment succeed but the service degraded? → Application bug
- Was there a rollback triggered by an alert? → Check SLO dashboards for what fired

**Step 3 — Check pipeline health**

```bash
# Confirm Pushgateway is receiving metrics correctly
curl http://localhost:9091/metrics | grep github_actions_deployments
```

If `NoPipelineActivity` fired and deployments are still happening, the `PUSHGATEWAY_URL` secret in GitHub Actions may be wrong or the Pushgateway is unreachable.

---

## Resolution

1. **For CFRThresholdWarning**: review the last 3 failed deployments. Add tests or feature flags to cover the regression pattern. No immediate action required beyond monitoring.

2. **For CFRThresholdExceeded**: initiate a reliability review:
   - Pause non-critical feature deployments until CFR drops below 5%
   - Require extra reviewer sign-off on all PRs until resolved
   - Add pre-deployment smoke tests to the pipeline

3. **For NoPipelineActivity**:
   - Check `PUSHGATEWAY_URL` secret: Settings → Secrets → Actions in GitHub
   - Confirm the Pushgateway is running: `systemctl status pushgateway`
   - Check GitHub Actions logs for the "Push DORA metrics" step

---

## Rollback decision

CFR is a lagging indicator — rolling back after the fact does not reduce CFR. Focus on fixing the root cause and improving test coverage. Only roll back an in-progress deployment if the service is currently degraded.

---

## Escalation

- Engineering lead should be notified when CFR exceeds 10%
- A post-incident review is required for every deployment that causes an SLO burn
- If CFR exceeds 15% for more than 3 consecutive days, initiate a full reliability sprint
