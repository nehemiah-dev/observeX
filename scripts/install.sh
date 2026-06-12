#!/usr/bin/env bash
# install.sh — ObserveX observability stack installer

set -euo pipefail

# TODO: confirm this resolves correctly when cloned — it sets REPO_DIR to
# the directory containing this script, so the repo can live anywhere.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="/var/log/observability-install.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

log "Starting installation from $REPO_DIR"

log "Preparing apt..."
systemctl stop unattended-upgrades 2>/dev/null || true
systemctl disable unattended-upgrades 2>/dev/null || true
killall apt apt-get unattended-upgrade 2>/dev/null || true
sleep 3
rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock \
      /var/cache/apt/archives/lock /var/lib/apt/lists/lock
dpkg --configure -a 2>/dev/null || true

log "Installing dependencies..."
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl wget unzip tar git python3 python3-pip python3-venv \
    jq net-tools apt-transport-https netcat-openbsd

for user in prometheus alertmanager loki tempo node_exporter blackbox; do
    id "$user" &>/dev/null || useradd --no-create-home --shell /bin/false "$user"
    log "User ready: $user"
done

mkdir -p /var/lib/{prometheus,alertmanager,loki,tempo}
mkdir -p /var/lib/tempo/{blocks,wal}
mkdir -p /etc/{prometheus/rules,alertmanager/templates,loki,tempo,blackbox}
mkdir -p /var/log/observability

chown prometheus:prometheus /var/lib/prometheus /etc/prometheus
chown alertmanager:alertmanager /var/lib/alertmanager /etc/alertmanager
chown loki:loki /var/lib/loki /etc/loki
chown tempo:tempo /var/lib/tempo /etc/tempo

download() {
    local url=$1 dest=$2
    for attempt in 1 2 3; do
        wget -q --timeout=60 --tries=3 -O "$dest" "$url" && return 0
        log "Download attempt $attempt failed for $url, retrying..."
        sleep 5
    done
    log "ERROR: Failed to download $url after 3 attempts"
    exit 1
}

install_binary() {
    local name="$1"
    if [ -x "/usr/local/bin/${name}" ]; then
        log "$name already installed, skipping download"
        return 0
    fi
    return 1
}

wait_for_port() {
    local svc=$1 port=$2
    local retries=15
    log "Waiting for $svc to bind port $port..."
    while ! nc -z localhost "$port" 2>/dev/null; do
        retries=$(( retries - 1 ))
        if (( retries <= 0 )); then
            log "WARNING: $svc did not bind port $port in time"
            return 1
        fi
        sleep 1
    done
    log "  ✓ $svc is listening on :$port"
}

# ── Prometheus ────────────────────────────────────────────────────────────────
PROMETHEUS_VERSION="3.12.0"
if ! install_binary prometheus; then
    log "Installing Prometheus ${PROMETHEUS_VERSION}..."
    (
        cd /tmp
        download "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz" \
            "prometheus.tar.gz"
        tar -xzf prometheus.tar.gz
        cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus" /usr/local/bin/
        cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool"   /usr/local/bin/
        chmod 755 /usr/local/bin/prometheus /usr/local/bin/promtool
        chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool
    )
fi

cp "$REPO_DIR/prometheus/prometheus.yml" /etc/prometheus/prometheus.yml

# TODO: prometheus/prometheus.yml — add a scrape job pointing to the app
# server's OTel Collector or app metrics endpoint, e.g.:
#   - job_name: 'app-server'
#     static_configs:
#       - targets: ['<APP_SERVER_IP>:8889']   # OTel Collector metrics export port

(
    shopt -s nullglob
    rule_files=("$REPO_DIR/prometheus/rules/"*.yml)
    if [ ${#rule_files[@]} -gt 0 ]; then
        cp "${rule_files[@]}" /etc/prometheus/rules/
    else
        log "WARNING: no rule files found in prometheus/rules/ — skipping"
    fi
)
chown -R prometheus:prometheus /etc/prometheus

cat > /etc/systemd/system/prometheus.service << 'UNIT'
[Unit]
Description=Prometheus Monitoring
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
Restart=always
RestartSec=5s
ExecStart=/usr/local/bin/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/var/lib/prometheus \
    --storage.tsdb.retention.time=30d \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries \
    --web.listen-address=0.0.0.0:9090 \
    --web.enable-remote-write-receiver \
    --enable-feature=exemplar-storage

[Install]
WantedBy=multi-user.target
UNIT
log "Prometheus configured"

# ── Node Exporter ─────────────────────────────────────────────────────────────
NODE_VERSION="1.11.1"
if ! install_binary node_exporter; then
    log "Installing Node Exporter ${NODE_VERSION}..."
    (
        cd /tmp
        download "https://github.com/prometheus/node_exporter/releases/download/v${NODE_VERSION}/node_exporter-${NODE_VERSION}.linux-amd64.tar.gz" \
            "node_exporter.tar.gz"
        tar -xzf node_exporter.tar.gz
        cp "node_exporter-${NODE_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
        chmod 755 /usr/local/bin/node_exporter
        chown node_exporter:node_exporter /usr/local/bin/node_exporter
    )
fi

cat > /etc/systemd/system/node_exporter.service << 'UNIT'
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
Restart=always
RestartSec=5s
ExecStart=/usr/local/bin/node_exporter --web.listen-address=0.0.0.0:9100

[Install]
WantedBy=multi-user.target
UNIT
log "Node Exporter configured"

# ── Blackbox Exporter ─────────────────────────────────────────────────────────
BLACKBOX_VERSION="0.28.0"
if ! install_binary blackbox_exporter; then
    log "Installing Blackbox Exporter ${BLACKBOX_VERSION}..."
    (
        cd /tmp
        download "https://github.com/prometheus/blackbox_exporter/releases/download/v${BLACKBOX_VERSION}/blackbox_exporter-${BLACKBOX_VERSION}.linux-amd64.tar.gz" \
            "blackbox_exporter.tar.gz"
        tar -xzf blackbox_exporter.tar.gz
        cp "blackbox_exporter-${BLACKBOX_VERSION}.linux-amd64/blackbox_exporter" /usr/local/bin/
        chmod 755 /usr/local/bin/blackbox_exporter
        chown blackbox:blackbox /usr/local/bin/blackbox_exporter
    )
fi

cat > /etc/blackbox/blackbox.yml << 'CONFIG'
modules:
  http_2xx:
    prober: http
    timeout: 5s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: []
      method: GET
      follow_redirects: true
      preferred_ip_protocol: "ip4"
CONFIG

cat > /etc/systemd/system/blackbox_exporter.service << 'UNIT'
[Unit]
Description=Blackbox Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=blackbox
Group=blackbox
Type=simple
Restart=always
RestartSec=5s
ExecStart=/usr/local/bin/blackbox_exporter \
    --config.file=/etc/blackbox/blackbox.yml \
    --web.listen-address=0.0.0.0:9115

[Install]
WantedBy=multi-user.target
UNIT
log "Blackbox Exporter configured"

# ── Alertmanager ──────────────────────────────────────────────────────────────
ALERTMANAGER_VERSION="0.32.2"
if ! install_binary alertmanager; then
    log "Installing Alertmanager ${ALERTMANAGER_VERSION}..."
    (
        cd /tmp
        download "https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz" \
            "alertmanager.tar.gz"
        tar -xzf alertmanager.tar.gz
        cp "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/alertmanager" /usr/local/bin/
        cp "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/amtool"       /usr/local/bin/
        chmod 755 /usr/local/bin/alertmanager /usr/local/bin/amtool
        chown alertmanager:alertmanager /usr/local/bin/alertmanager /usr/local/bin/amtool
    )
fi

cp "$REPO_DIR/alertmanager/alertmanager.yml" /etc/alertmanager/

(
    shopt -s nullglob
    tmpl_files=("$REPO_DIR/alertmanager/templates/"*.tmpl)
    if [ ${#tmpl_files[@]} -gt 0 ]; then
        cp "${tmpl_files[@]}" /etc/alertmanager/templates/
    else
        log "WARNING: no .tmpl files found in alertmanager/templates/ — skipping"
    fi
)

# TODO: set SLACK_WEBHOOK_URL in your environment before running,
# or the alertmanager.yml placeholder will remain and alerts will not fire.
if [ -n "${SLACK_WEBHOOK_URL}" ] && [ "${SLACK_WEBHOOK_URL}" != "replace this" ]; then
    sed -i "s|slack_api_url: 'replace this'|slack_api_url: '${SLACK_WEBHOOK_URL}'|" \
        /etc/alertmanager/alertmanager.yml
    log "Slack webhook URL injected into alertmanager.yml"
else
    log "WARNING: SLACK_WEBHOOK_URL not set — alertmanager.yml still has placeholder. Alerts will not fire."
fi

chown -R alertmanager:alertmanager /etc/alertmanager /var/lib/alertmanager

cat > /etc/systemd/system/alertmanager.service << 'UNIT'
[Unit]
Description=Alertmanager
Wants=network-online.target
After=network-online.target

[Service]
User=alertmanager
Group=alertmanager
Type=simple
Restart=always
RestartSec=5s
ExecStart=/usr/local/bin/alertmanager \
    --config.file=/etc/alertmanager/alertmanager.yml \
    --storage.path=/var/lib/alertmanager \
    --web.listen-address=0.0.0.0:9093

[Install]
WantedBy=multi-user.target
UNIT
log "Alertmanager configured"

# ── Loki ──────────────────────────────────────────────────────────────────────
# TODO: on the app server, configure your log shipper (Promtail, Alloy, etc.)
# to forward logs to this Loki instance:
#   url: http://<THIS_SERVER_IP>:3100/loki/api/v1/push

LOKI_VERSION="3.7.2"
if ! install_binary loki; then
    log "Installing Loki ${LOKI_VERSION}..."
    (
        cd /tmp
        download "https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-linux-amd64.zip" \
            "loki.zip"
        unzip -q -o loki.zip
        cp loki-linux-amd64 /usr/local/bin/loki
        chmod +x /usr/local/bin/loki
        chown loki:loki /usr/local/bin/loki
    )
fi

cp "$REPO_DIR/loki/loki-config.yml" /etc/loki/
chown -R loki:loki /etc/loki /var/lib/loki

cat > /etc/systemd/system/loki.service << 'UNIT'
[Unit]
Description=Loki Log Aggregator
Wants=network-online.target
After=network-online.target

[Service]
User=loki
Group=loki
Type=simple
Restart=always
RestartSec=5s
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/loki-config.yml

[Install]
WantedBy=multi-user.target
UNIT
log "Loki configured"

# ── Tempo ─────────────────────────────────────────────────────────────────────
# TODO: on the app server, configure the OTel Collector to export traces here:
#   exporters:
#     otlp:
#       endpoint: "<THIS_SERVER_IP>:4317"
#       tls:
#         insecure: true

TEMPO_VERSION="2.4.1"
if ! install_binary tempo; then
    log "Installing Tempo ${TEMPO_VERSION}..."
    (
        cd /tmp
        download "https://github.com/grafana/tempo/releases/download/v${TEMPO_VERSION}/tempo_${TEMPO_VERSION}_linux_amd64.tar.gz" \
            "tempo.tar.gz"
        tar -xzf tempo.tar.gz
        cp tempo /usr/local/bin/
        chmod +x /usr/local/bin/tempo
        chown tempo:tempo /usr/local/bin/tempo
    )
fi

cp "$REPO_DIR/tempo/tempo-config.yml" /etc/tempo/
chown -R tempo:tempo /etc/tempo /var/lib/tempo

cat > /etc/systemd/system/tempo.service << 'UNIT'
[Unit]
Description=Tempo Distributed Tracing
Wants=network-online.target
After=network-online.target

[Service]
User=tempo
Group=tempo
Type=simple
Restart=always
RestartSec=5s
ExecStart=/usr/local/bin/tempo -config.file=/etc/tempo/tempo-config.yml

[Install]
WantedBy=multi-user.target
UNIT
log "Tempo configured"

# ── Grafana ───────────────────────────────────────────────────────────────────
if ! command -v grafana-server &>/dev/null; then
    log "Installing Grafana..."
    wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
    echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" \
        > /etc/apt/sources.list.d/grafana.list
    DEBIAN_FRONTEND=noninteractive apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y grafana
fi

mkdir -p /etc/grafana/provisioning/{datasources,dashboards}
mkdir -p /var/lib/grafana/dashboards

cp "$REPO_DIR/grafana/provisioning/datasources/"*.yml /etc/grafana/provisioning/datasources/
cp "$REPO_DIR/grafana/provisioning/dashboards/"*.yml  /etc/grafana/provisioning/dashboards/
cp "$REPO_DIR/grafana/dashboards/"*.json              /var/lib/grafana/dashboards/
chown -R grafana:grafana /etc/grafana/provisioning /var/lib/grafana

# TODO: set GRAFANA_ADMIN_PASSWORD in your environment before running.
# Leaving it unset defaults to 'admin' which is insecure in production.
GRAFANA_PASS="${GRAFANA_ADMIN_PASSWORD:-admin}"

SAFE_PASS=$(printf '%s' "$GRAFANA_PASS" | sed 's/[&\\/]/\\&/g')
sed -i "s|^;*admin_password = .*|admin_password = ${SAFE_PASS}|" /etc/grafana/grafana.ini
sed -i 's|^;*admin_user = .*|admin_user = admin|'               /etc/grafana/grafana.ini
log "Grafana configured"

# ── Enable and start all services ─────────────────────────────────────────────
log "Starting all services..."
systemctl daemon-reload

SERVICES=(
    prometheus
    node_exporter
    blackbox_exporter
    alertmanager
    loki
    tempo
    grafana-server
)

declare -A SVC_PORT=(
    [prometheus]=9090
    [node_exporter]=9100
    [blackbox_exporter]=9115
    [alertmanager]=9093
    [loki]=3100
    [tempo]=3200
    [grafana-server]=3000
)

for svc in "${SERVICES[@]}"; do
    systemctl enable "$svc"
    systemctl restart "$svc"
    port="${SVC_PORT[$svc]:-}"
    if [ -n "$port" ]; then
        wait_for_port "$svc" "$port" || true
    fi
    if systemctl is-active --quiet "$svc"; then
        log "✓ $svc running"
    else
        log "✗ $svc FAILED"
        journalctl -u "$svc" -n 20 --no-pager | tee -a "$LOG_FILE"
    fi
done

# ── Force Grafana admin password via CLI (works on re-runs and existing DBs) ──
log "Setting Grafana admin password via grafana-cli..."
systemctl stop grafana-server
sleep 2
GRAFANA_BIN=$(command -v grafana || echo "/usr/bin/grafana")
set +e
CLI_OUTPUT=$(
    "${GRAFANA_BIN}" cli \
        --homepath /usr/share/grafana \
        --config /etc/grafana/grafana.ini \
        admin reset-admin-password "${GRAFANA_PASS}" 2>&1
)
CLI_EXIT=$?
set -e
log "grafana cli output: ${CLI_OUTPUT}"
if [ $CLI_EXIT -eq 0 ]; then
    log "Grafana admin password confirmed: admin/${GRAFANA_PASS}"
else
    log "WARNING: grafana cli reset failed (exit ${CLI_EXIT})"
fi
systemctl start grafana-server
wait_for_port grafana-server 3000 || true

# ── Resolve public IP ─────────────────────────────────────────────────────────
# TODO: set SERVER_HOST in terraform.tfvars to avoid relying on metadata
# endpoint fallback, which may not be available outside AWS/GCP.
if [ -n "${SERVER_HOST:-}" ]; then
    PUBLIC_IP="${SERVER_HOST}"
    log "Using SERVER_HOST for public IP: ${PUBLIC_IP}"
else
    PUBLIC_IP=$(curl -sf --max-time 5 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
    if [ -z "${PUBLIC_IP}" ]; then
        PUBLIC_IP=$(curl -sf --max-time 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]')
    fi
    if [ -z "${PUBLIC_IP}" ]; then
        log "WARNING: Could not resolve public IP — dashboard links will use private IP."
        PUBLIC_IP=$(hostname -I | awk '{print $1}')
    fi
fi

GRAFANA_URL="http://${PUBLIC_IP}:3000"
log "Patching dashboard URLs to ${GRAFANA_URL}..."
for f in /etc/prometheus/rules/*.yml /etc/alertmanager/alertmanager.yml; do
    sed -i "s|http://localhost:3000|${GRAFANA_URL}|g" "$f"
done

if promtool check config /etc/prometheus/prometheus.yml > /dev/null 2>&1; then
    systemctl restart prometheus
    log "Prometheus config validated and reloaded"
else
    log "ERROR: Prometheus config invalid after URL patch — NOT reloading. Check /etc/prometheus/prometheus.yml"
fi

if amtool check-config /etc/alertmanager/alertmanager.yml > /dev/null 2>&1; then
    systemctl restart alertmanager
    log "Alertmanager config validated and reloaded"
else
    log "ERROR: Alertmanager config invalid after URL patch — NOT reloading. Check /etc/alertmanager/alertmanager.yml"
fi

log "======================================"
log "Installation complete"
log "Grafana:      http://${PUBLIC_IP}:3000  (admin/${GRAFANA_PASS})"
log "Prometheus:   http://${PUBLIC_IP}:9090"
log "Alertmanager: http://${PUBLIC_IP}:9093"
log "Loki:         http://${PUBLIC_IP}:3100"
log "Tempo:        http://${PUBLIC_IP}:3200"
log "======================================"
