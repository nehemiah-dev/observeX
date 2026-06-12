variable "server_host" {
  description = "IP address or hostname of the target server where the stack will be installed"
  type        = string
}

variable "slack_webhook_url" {
  description = "Slack incoming webhook URL for Alertmanager to send notifications to #DevOps-Alerts"
  type        = string
  sensitive   = true

}

variable "grafana_admin_password" {
  description = "Admin password for the Grafana UI (minimum 8 characters). Set this in terraform.tfvars — do not use the default in production."
  type        = string
  sensitive   = true
}

variable "blackbox_targets" {
  description = "List of URLs for Blackbox Exporter to probe for uptime and SSL"
  type        = list(string)
  default     = ["http://localhost:8080/health", "http://localhost:8080/"]
}

variable "pushgateway_url" {
  description = "URL of the Prometheus Pushgateway (used by GitHub Actions to push DORA metrics)"
  type        = string
  default     = "http://localhost:9091"
}

variable "prometheus_retention" {
  description = "How long Prometheus retains metrics data (e.g. 30d, 90d)"
  type        = string
  default     = "30d"
}

variable "loki_retention_hours" {
  description = "How long Loki retains log data in hours (e.g. 720 = 30 days)"
  type        = number
  default     = 720
}

variable "tempo_block_retention_hours" {
  description = "How long Tempo retains trace blocks in hours (e.g. 168 = 7 days)"
  type        = number
  default     = 168
}

variable "scripts_base_path" {
  description = "Absolute path on the target server where the install scripts live"
  type        = string
  default     = "/tmp/observeX/scripts"
}
