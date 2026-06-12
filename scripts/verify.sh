#!/usr/bin/env bash
# verify.sh — ObserveX observability stack health check
# Fixes applied:
#   #13  otelcol — health extension port 13133 added; was silently unverified
#   #14  PUBLIC_IP curl — --max-time 3 added; avoids 75s hang on non-AWS hosts
#   #15  PASS/FAIL counters — moved to temp file so they survive subshells
#         (guards against future piping: e.g. verify.sh | tee install.log)

set -euo pipefail

echo "============================================"
echo "  Observability Platform — Verify"
echo "============================================"

# FIX #15: use a temp file for counters so they survive if this script is
# ever piped (which would run it in a subshell and lose variable mutations).
# Also safe in the current non-piped usage.
COUNTER_FILE=$(mktemp)
echo "PASS=0" > "$COUNTER_FILE"
echo "FAIL=0" >> "$COUNTER_FILE"
trap 'rm -f "$COUNTER_FILE"' EXIT

inc_pass() { source "$COUNTER_FILE"; PASS=$((PASS+1)); echo "PASS=$PASS" > "$COUNTER_FILE"; echo "FAIL=$FAIL" >> "$COUNTER_FILE"; }
inc_fail() { source "$COUNTER_FILE"; FAIL=$((FAIL+1)); echo "PASS=$PASS" > "$COUNTER_FILE"; echo "FAIL=$FAIL" >> "$COUNTER_FILE"; }

check() {
    local name="$1"
    local port="$2"
    local path="${3:-/}"

    # Service active check
    if systemctl is-active --quiet "$name" 2>/dev/null; then
        echo "  ✓ $name is active"
        inc_pass
    else
        echo "  ✗ $name is NOT active"
        inc_fail
    fi

    # HTTP endpoint check (only when a port is provided)
    if [ -n "$port" ]; then
        if curl -sf --max-time 5 "http://localhost:${port}${path}" > /dev/null 2>&1; then
            echo "  ✓ localhost:${port}${path} responding"
            inc_pass
        else
            echo "  ✗ localhost:${port}${path} NOT responding"
            inc_fail
        fi
    fi
}

echo ""
check "prometheus"        "9090" "/-/healthy"
check "node_exporter"     "9100" "/metrics"
check "blackbox_exporter" "9115" "/metrics"
check "alertmanager"      "9093" "/-/healthy"
check "loki"              "3100" "/ready"
check "tempo"             "3200" "/ready"
check "grafana-server"    "3000" "/api/health"
# FIX #13: otelcol exposes a health-check extension on port 13133.
# Previously passed "" so it received zero HTTP verification — only the
# systemd active check ran. Now we verify the health endpoint too.
check "otelcol"           "13133" "/health/status"
check "pushgateway"       "9091"  "/metrics"
check "demo-app"          "8080"  "/health"

echo ""
source "$COUNTER_FILE"
echo "Passed: $PASS  Failed: $FAIL"

# FIX #14: add --max-time 3 to the metadata curl call.
# Without it, on any non-AWS host the request hangs for ~75 seconds
# (default TCP connect timeout) before falling back to hostname -I.
PUBLIC_IP=$(
    curl -sf --max-time 3 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null \
    || hostname -I | awk '{print $1}'
)

echo ""
echo "Grafana:      http://${PUBLIC_IP}:3000"
echo "Prometheus:   http://${PUBLIC_IP}:9090"
echo "Alertmanager: http://${PUBLIC_IP}:9093"