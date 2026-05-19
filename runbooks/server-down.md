# Runbook: Server Down

## What is this alert?
The Blackbox Exporter probe has failed for 2 or more consecutive minutes. The service is not responding to HTTP requests.

## Likely causes
- Service crashed and systemd has not restarted it yet
- Port not listening — application failed to start
- Network firewall rule blocking the probe
- Service in a crash loop

## First 3 investigation steps
1. Run `sudo systemctl status demo-app` — is it running or failed?
2. Run `sudo journalctl -u demo-app -n 50` — what does the crash log say?
3. Run `curl http://localhost:8080/health` from the server — does it respond locally?

## Resolution
- Service stopped: `sudo systemctl start demo-app`
- Service crash looping: check logs, roll back deployment
- Network issue: check firewall rules with `sudo ufw status`

## Should I roll back?
Roll back if the service is crashing repeatedly after restart attempts.

## Escalation
Escalate immediately if service is not restored within 5 minutes. Users are affected.
