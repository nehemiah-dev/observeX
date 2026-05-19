# Runbook: Disk High

## What is this alert?
Disk usage has exceeded warning (75%) or critical (90%) threshold.

## Likely causes
- Log files accumulating without rotation
- Prometheus or Loki data growing beyond retention settings
- Temporary files not being cleaned up

## First 3 investigation steps
1. Run `df -h` to confirm which filesystem is full
2. Run `du -sh /* 2>/dev/null | sort -rh | head -20` to find largest directories
3. Run `sudo journalctl --disk-usage` to check journal size

## Resolution
- Clean system journal: `sudo journalctl --vacuum-size=500M`
- Check Prometheus data: `du -sh /var/lib/prometheus`
- Check Loki data: `du -sh /var/lib/loki`
- Remove old temp files: `sudo find /tmp -mtime +7 -delete`

## Should I roll back?
Not typically a rollback scenario. Address disk usage directly.

## Escalation
Escalate if disk reaches 95% and cannot be cleared within 15 minutes.
