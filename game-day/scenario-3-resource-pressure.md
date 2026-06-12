# Game Day — Scenario 3: Resource Pressure

**Date:** ___________  
**Executed by:** Nehemiah  
**Objective:** Apply CPU stress to the host, confirm warning fires before critical, verify both alerts appear in Slack, then remove pressure and confirm both RESOLVED notifications arrive. Also verify inhibition rules suppress duplicate alerts.

---

## Pre-Conditions

```bash
# Install stress tool if not present
sudo apt-get install -y stress

# Check number of CPU cores available
nproc

# Confirm Node Exporter is running and scraping
curl -s http://localhost:9100/metrics | grep node_cpu_seconds_total | head -5
```

- [ ] Node Exporter running and scraping
- [ ] Node Exporter dashboard open at `https://observex.duckdns/d/node-exporter`
- [ ] Prometheus Alerts page open at `http://localhost:9090/alerts`
- [ ] Slack `#DevOps-Alerts` channel being monitored

---

## Phase 1 — Warning Level (CPU > 80%)

### Step 1 — Apply moderate CPU pressure

Use fewer CPU workers than available cores to target ~85% usage without hitting 90%.

```bash
# Example: on a 4-core machine, use 3 workers
CORES=$(nproc)
WORKERS=$(( CORES - 1 ))

stress --cpu $WORKERS --timeout 600s &
STRESS_PID=$!
echo "Stress PID: $STRESS_PID"
```

**Timestamp started:** ___________

---

### Step 2 — Confirm CPU crosses 80%

```bash
# Watch CPU in real time
watch -n 5 'curl -s "http://localhost:9090/api/v1/query?query=100 - (avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)" | python3 -m json.tool'
```

Or open the Node Exporter dashboard → CPU Total panel.

**Screenshot:** CPU Total panel showing usage above 80%.  
**Timestamp CPU > 80%:** ___________

---

### Step 3 — Wait for CPUWarning to fire

The rule has `for: 5m` — alert fires 5 minutes after CPU stays above 80%.

```bash
# Check alert state
curl -s http://localhost:9090/api/v1/alerts | python3 -m json.tool | grep -A8 "CPUWarning"
```

**Screenshot:** Prometheus Alerts showing `CPUWarning` PENDING then FIRING.  
**Screenshot:** Slack warning notification — severity: WARNING, yellow background.  
**Timestamp FIRING:** ___________

---

## Phase 2 — Critical Level (CPU > 90%)

### Step 4 — Increase pressure above 90%

```bash
# Kill the existing stress process
kill $STRESS_PID

# Restart with ALL cores to push above 90%
stress --cpu $(nproc) --timeout 600s &
STRESS_PID=$!
```

**Timestamp started:** ___________

---

### Step 5 — Wait for CPUCritical to fire

The rule has `for: 10m` — alert fires 10 minutes after CPU stays above 90%.

```bash
curl -s http://localhost:9090/api/v1/alerts | python3 -m json.tool | grep -A8 "CPUCritical"
```

**Screenshot:** Prometheus Alerts showing BOTH `CPUWarning` and `CPUCritical` FIRING.  
**Screenshot:** Slack showing the critical alert — severity: CRITICAL, red background.

> **Important:** Verify inhibition is working. `CPUCritical` should **suppress** `CPUWarning` in Alertmanager.
> Check `http://localhost:9093/#/alerts` — `CPUWarning` should show as inhibited.

**Screenshot:** Alertmanager UI showing `CPUWarning` inhibited by `CPUCritical`.  
**Timestamp CPUCritical FIRING:** ___________

---

## Phase 3 — Recovery

### Step 6 — Remove CPU pressure

```bash
kill $STRESS_PID
killall stress 2>/dev/null || true
```

**Timestamp removed:** ___________

---

### Step 7 — Confirm CPU drops below 75%

```bash
# Watch CPU value drop
watch -n 5 'curl -s "http://localhost:9090/api/v1/query?query=100-(avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m]))*100)" | python3 -m json.tool'
```

**Screenshot:** CPU panel returning to normal (<75%).

---

### Step 8 — Confirm both RESOLVED notifications in Slack

Both `CPUWarning` and `CPUCritical` should resolve and send `✅ [RESOLVED]` notifications.

- [ ] `CPUWarning` RESOLVED in Slack
- [ ] `CPUCritical` RESOLVED in Slack
- [ ] Both notifications show duration (StartsAt → ResolvedAt)

**Screenshot:** Both resolved notifications in `#DevOps-Alerts`.  
**Timestamp CPUCritical RESOLVED:** ___________  
**Timestamp CPUWarning RESOLVED:** ___________

---

## Inhibition Rule Verification (Bonus)

### Verify HostDown suppresses CPU/Memory alerts

Simulate a HostDown condition by stopping the Blackbox Exporter:

```bash
# Stop Blackbox Exporter to trigger HostDown
sudo systemctl stop blackbox-exporter
```

Wait 2 minutes for `HostDown` to fire. Then apply CPU pressure:

```bash
stress --cpu $(nproc) --timeout 300s &
```

**Expected:** `CPUWarning` and `CPUCritical` do NOT appear in Slack because they are suppressed by `HostDown` via the inhibition rule.

**Screenshot:** Alertmanager inhibited alerts list showing CPU alerts suppressed.

Restore:

```bash
sudo systemctl start blackbox-exporter
killall stress 2>/dev/null || true
```

---

## Timeline Summary

| Time | Event |
|---|---|
| T+0:00 | Moderate stress started (< 90%) |
| T+0:XX | CPU crosses 80% |
| T+0:XX | `CPUWarning` enters PENDING |
| T+0:XX | `CPUWarning` FIRES → Slack warning notification |
| T+0:XX | CPU pressure increased to 100% |
| T+0:XX | CPU crosses 90% |
| T+0:XX | `CPUCritical` enters PENDING |
| T+0:XX | `CPUCritical` FIRES → Slack critical notification |
| T+0:XX | `CPUWarning` inhibited by CPUCritical (Alertmanager) |
| T+0:XX | Stress removed |
| T+0:XX | CPU drops below 75% |
| T+0:XX | Both alerts RESOLVED → Slack resolved notifications |

---

## Observations

**Did warning fire BEFORE critical?**
- [ ] Yes — correct alert ordering confirmed
- [ ] No — investigate rule `for:` durations

**Did inhibition suppress CPUWarning when CPUCritical was firing?**
- [ ] Yes
- [ ] No — check inhibition rule in alertmanager.yml

**Time from 90% CPU to CPUCritical firing:** ___________  
**Time from stress removed to alerts resolved:** ___________

**Action items:**
- 
