# Runbook: SLO Fast Burn

## What is this alert?
The service is consuming its 30-day error budget at 14.4x the normal rate. At this pace the entire monthly error budget will be exhausted in approximately 2 hours.

## Likely causes
- Recent bad deployment causing elevated error rates
- Downstream dependency failure
- Infrastructure issue such as disk full, OOM, or network partition

## First 3 investigation steps
1. Open the SLO dashboard — identify which SLI is burning (availability or latency)
2. Open the Unified dashboard — correlate the error spike with logs in Loki
3. Check recent deployments — did anything go out in the last 2 hours?

## Resolution
- Bad deployment: roll back immediately with `sudo systemctl restart demo-app` after reverting code
- Dependency failure: identify and circuit break or fail gracefully
- Infrastructure issue: address root cause directly (free disk, fix OOM)

## Should I roll back?
Roll back immediately if a deployment happened in the last 2 hours and error rate is above 5%.

## Escalation
Page on-call engineer immediately. This alert means the monthly error budget exhausts in 2 hours.
