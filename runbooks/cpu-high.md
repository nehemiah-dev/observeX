# Runbook: CPU High

## What is this alert?
CPU usage on the host has exceeded warning (80%) or critical (90%) threshold for a sustained period.

## Likely causes
- Application traffic spike
- Runaway process consuming CPU in a loop
- Background job competing with application
- Memory pressure causing excessive swapping

## First 3 investigation steps
1. SSH to the host and run `top` or `htop` to identify the consuming process
2. Check recent deployments — did a new release coincide with the spike?
3. Check Grafana Node Exporter dashboard for CPU trend — sudden spike or gradual climb?

## Resolution
- Runaway process: `sudo kill -9 PID` then investigate why
- Traffic spike: rate limit at the application level
- Recent deployment: consider rollback

## Should I roll back?
Roll back if CPU stays above 90% for more than 15 minutes with no other resolution found.

## Escalation
Escalate to senior engineer if unresolved after 30 minutes.
