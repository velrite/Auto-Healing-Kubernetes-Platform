# Verified Run: October 2026

A full rebuild of the platform from this repo on a fresh GitHub Codespace, with every claim re-measured.
Screenshots are in `docs/evidence/`. Where a number differs from earlier documentation, this file is correct.

## Results

| Test | Measured | Evidence |
|---|---|---|
| Cluster | 3 nodes Ready, Kubernetes v1.31.0 | 01-cluster-nodes.png |
| Namespaces | microservices, monitoring, vault, opencost | 02-namespaces.png |
| Pods | All platform pods Running | 03-all-pods-running.png |
| HPA config | api-service 2-8 (CPU 60%, mem 70%), frontend 2-6 (CPU 65%) | 04-hpa-config.png |
| Alert rules | 6 custom alerts in microservices-alerts; 140 alerting rules loaded in total | 05-alert-rules.png |
| HPA baseline | 2 replicas, CPU 2% | 06-hpa-before-load.png |
| HPA under load | CPU 366% of request, replicas 2 to 8 | 07-hpa-during-load.png |
| HPA scale-down | Back to 2 replicas without manual scaling | 08-hpa-scale-down.png |
| Node failure | Recovery in 361 seconds. The 120s SLO was NOT met: Kubernetes waits about 5 minutes by default before evicting pods from a dead node. The earlier 20s claim was not reproduced | 09-node-recovery.png |
| Bad deploy | New pod ErrImagePull, 2 old pods kept Running, rolled back in 30 seconds | 10-bad-deploy-rollback.png |
| Zero credentials | No password value in pod description | 11-zero-credentials.png |
| Vault dynamic secrets | Different username and password on each read, 1h TTL | 12-vault-dynamic-secrets.png |
| Secret rotation | KV v2 version 1 to 2, pods unaffected | 13-secret-rotation.png |
| OpenCost | Real per-pod cost from the allocation API | 14-opencost-data.png |
| CI pipeline | Run from the original repo's Actions history | 15-github-actions-green.png |
| Grafana | Golden Signals dashboard; only Saturation has data | 16-grafana-dashboard.png |
| Prometheus targets | 21 targets up, 0 down | 17-prometheus-targets.png |

## Changes made to reach these results

| Change | Why | Effect on the claim |
|---|---|---|
| api-service memory request raised to 128Mi (limit 256Mi) | At the default request, memory sat above the 70% HPA target and blocked scale-down even at 2% CPU | Scale-down is now driven by load, not by a memory baseline |
| Added a `postgres-db` Service to database.yaml | The repo had no Service, so Vault could not resolve `postgres-db.microservices.svc.cluster.local` | Vault dynamic database credentials now work |
| `?sslmode=disable` on the Vault connection URL | Postgres 14 here has no TLS and the driver requests it by default | Required for the DB engine connection |
| Grafana dashboard imported through the API | The ConfigMap did not load into Grafana | Same four queries, imported directly |
| etcd, scheduler, controller-manager, kube-proxy monitoring disabled | Minikube does not expose them, so they would show DOWN | All 21 remaining targets are up |

## Corrections to earlier documentation

- **Vault database engine.** Earlier docs said it failed because Vault was reached by port-forward. The real cause was the missing Service. Vault runs in-cluster and resolves DNS itself.
- **Alert rule count.** The earlier "36 rules" was not supported. The repo defines 6 custom alerts; with the stack's built-in rules Prometheus loads 140.
- **Timings.** Measured values change per run. This run recorded 30s for rollback.

## Limits of this evidence

- Single run on one Codespace; no repeated trials, so no variance is claimed.
- Only Saturation has data in Grafana. nginx exposes no application metrics.
- The CI pipeline does not deploy to this cluster; a Codespace cluster is not reachable from a GitHub runner.
- Vault runs in dev mode, so its configuration is lost on restart.
