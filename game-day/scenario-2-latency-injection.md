# Game Day — Scenario 2: Latency Injection

**Date:** ___________  
**Executed by:** Nehemiah  
**Objective:** Simulate high latency, observe the SLI degrade, the SLO burn rate increase, the `SLOFastBurn` alert fire in Slack, and then complete the full drill-down: metric spike → Loki logs → trace ID → Tempo waterfall.

This is the most important scenario. The full drill-down path is a **non-negotiable acceptance criterion**.

---

## Pre-Conditions

- [ ] All LGTP services active and healthy
- [ ] Instrumented application is running and emitting traces
- [ ] Loki derived field (TraceID → Tempo) is confirmed working
- [ ] Unified Observability dashboard is open at `https://observex.duckdns.org/d/unified-observability`
- [ ] SLO & Error Budget dashboard is open at `https://observex.duckdns/d/slo-error-budget`

---

## Latency Injection Methods

### Method A — Network-Level (tc netem) — Recommended

This injects latency at the OS network layer and affects all traffic on the loopback interface.

```bash
# Inject 600ms latency on loopback (affects localhost connections)
sudo tc qdisc add dev lo root netem delay 600ms

# Verify latency is applied
ping -c 3 localhost
# Round-trip should now be ~600ms
```

### Method B — Application-Level

If `tc` is unavailable, add a sleep to your application:

```python
# Python/Flask example — add to a route handler
import time
time.sleep(0.6)  # 600ms
```

---

## Steps

### Step 1 — Apply latency injection

```bash
sudo tc qdisc add dev lo root netem delay 600ms
```

**Timestamp started:** ___________

---

### Step 2 — Observe latency SLI degrade in Grafana

Open the Unified Observability dashboard → P99 Latency panel.

Wait 1–2 minutes for the 5m rate window to show the degradation.

- [ ] P99 latency crosses 500ms threshold (line turns yellow/red)
- [ ] P95 latency also elevated
- [ ] Error ratio may increase if timeouts are configured

**Screenshot:** Latency panel showing spike above 500ms.  
**Timestamp SLI degraded:** ___________

---

### Step 3 — Observe burn rate increase

Open the SLO & Error Budget dashboard → Burn Rate panel.

```bash
# Check burn rate value directly
curl -s 'http://localhost:9090/api/v1/query?query=job:http_error_ratio:rate1h/0.01' \
  | python3 -m json.tool
```

- [ ] Burn rate panel shows value climbing above 5 (Slow Burn threshold)
- [ ] Burn rate crosses 14.4 (Fast Burn threshold)

**Screenshot:** Burn rate time series showing both thresholds crossed.  
**Timestamp burn rate > 14.4:** ___________

---

### Step 4 — Confirm SLOFastBurn alert fires

```bash
# Check alert state
curl -s http://localhost:9090/api/v1/alerts | python3 -m json.tool | grep -A8 "SLOFastBurn"
```

Alert has `for: 2m` — it will fire 2 minutes after the condition is first true.

**Screenshot:** Prometheus Alerts page showing `SLOFastBurn` FIRING.  
**Screenshot:** Slack `#DevOps-Alerts` showing the critical alert with full payload.  
**Timestamp FIRING:** ___________

---

### Step 5 — Drill-Down Step A: Click into Loki from metric panel

1. On the Unified Observability dashboard, click the **Error Rate** or **P99 Latency** panel.
2. Click the **"Explore errors in Loki"** link that appears.
3. Grafana opens Loki Explore with the time window pre-filled.

**Screenshot:** Loki Explore showing log lines from the affected time window.  
**Timestamp:** ___________

---

### Step 6 — Drill-Down Step B: Find a log line with traceID

In the Loki Explore view:

1. Look for log lines containing `traceID=` (these come from the instrumented application).
2. Expand a log line — the `traceID=` value should appear as a **clickable blue link** labelled "Open in Tempo".

If the link does not appear:
```bash
# Verify the derived field is configured correctly
curl -s https://observex.duckdns/api/datasources | python3 -m json.tool | grep -A5 "derivedFields"
```

**Screenshot:** Loki log line expanded, showing `traceID=` as a clickable link.  
**Timestamp:** ___________

---

### Step 7 — Drill-Down Step C: Open trace in Tempo

1. Click the "Open in Tempo" link.
2. Grafana opens the Tempo trace view showing the full span waterfall.

In the trace waterfall:
- [ ] The root span shows total duration > 600ms
- [ ] The slow child span is highlighted (longest bar)
- [ ] The span tags show `service.name`, `http.url`, `http.status_code`

**Screenshot:** Tempo trace waterfall with all spans visible.  
**Screenshot:** Slow span expanded showing tags and duration.  
**Timestamp:** ___________

---

### Step 8 — Remove latency injection

```bash
# Remove the tc rule
sudo tc qdisc del dev lo root

# Verify latency is gone
ping -c 3 localhost
# Round-trip should be < 1ms again
```

**Timestamp removed:** ___________

---

### Step 9 — Confirm recovery

- [ ] P99 latency drops back below 500ms in Grafana
- [ ] Burn rate returns below 1.0
- [ ] `SLOFastBurn` alert resolves in Prometheus
- [ ] `✅ [RESOLVED]` notification appears in Slack

**Screenshot:** Resolved alert in Slack with duration shown.  
**Timestamp resolved:** ___________

---

## Full Drill-Down Timeline

| Step | Action | Screenshot |
|---|---|---|
| 1 | Latency injected | Terminal showing tc command |
| 2 | SLI degrades (>500ms) | Latency panel spike |
| 3 | Burn rate > 14.4x | Burn rate time series |
| 4 | SLOFastBurn FIRING | Prometheus Alerts + Slack |
| 5 | Loki Explore opened | Log lines in time window |
| 6 | traceID link visible | Expanded log line |
| 7 | Tempo trace opened | Full span waterfall |
| 8 | Slow span identified | Span detail view |
| 9 | Injection removed | Terminal |
| 10 | Alert RESOLVED | Slack resolved notification |

---

## Error Budget Impact

```bash
# Check how much budget was consumed during this scenario
curl -s 'http://localhost:9090/api/v1/query?query=clamp_min((1 - job:http_error_ratio:rate3d / 0.01) * 100, 0)' \
  | python3 -m json.tool
```

**Budget before:** ___________%  
**Budget after:**  ___________%  
**Budget consumed:** ___________%

---

## Observations

**What worked well:**
- 

**Was the drill-down path fully functional?**
- [ ] Yes — all 4 steps worked end-to-end
- [ ] Partial — issue at step: ___________

**How long from injection to alert fire?** ___________  
**How long from alert fire to trace identification?** ___________

**Action items:**
- 
