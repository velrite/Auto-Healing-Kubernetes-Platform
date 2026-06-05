# Auto-Healing Kubernetes Platform

A production-grade Kubernetes platform designed around failure as a
first-class concern — not an afterthought.

## Problem Statement

Most infrastructure is built to work under ideal conditions.
Production is not ideal.

Production means node loss, traffic spikes, bad deployments,
and cloud costs that grow faster than engineering output.

This platform is designed around those conditions from day one.

## Architecture Overview
Users → API Gateway → Auth Layer
→ Load Balancer
→ Microservices (Kubernetes Pods)
→ Application Services (api-service, frontend)
→ Background Workers
→ Data Layer (PostgreSQL + Redis)
→ Observability Stack
→ Prometheus (metrics + alerting)
→ Grafana (Golden Signals dashboards)
→ ELK Stack (logs)
→ Cost Visibility (OpenCost)
→ Secrets Management (HashiCorp Vault)
## What This Platform Does

**Automated Failure Recovery**
- Detects node failure and reschedules pods automatically
- No manual intervention required for single node loss
- Reconciliation loop corrects actual vs desired state continuously
- Recovery validated across multiple test runs: 20–46 seconds

**Deployment Safety**
- 5-stage GitHub Actions CI/CD pipeline with enforced quality gates
- Canary deployments with traffic splitting
- Automated rollback triggered by pod readiness failure sustained beyond threshold
- Zero static credentials via HashiCorp Vault dynamic secrets

**Observability**
- Golden Signals monitored per service
  - Latency (p50/p95/p99)
  - Error rate (4xx/5xx)
  - Traffic (requests per second)
  - Saturation (CPU/memory/queue depth)
- 36 Prometheus alert rules routed around noise — focused on SLO-impacting conditions
- Alerting before issues become incidents

**Cost Visibility (FinOps)**
- Per-namespace and per-service cost breakdown via OpenCost
- Cost labels applied per service, team, and environment
- Idle resource detection and right-sizing recommendations
- Real cost data confirmed via API

## Tech Stack

| Layer | Technology |
|-------|------------|
| Container Orchestration | Kubernetes v1.31.0 |
| Environment | GitHub Codespaces (Minikube) |
| CI/CD | GitHub Actions |
| Secrets Management | HashiCorp Vault |
| Monitoring | Prometheus + Grafana |
| Cost Visibility | OpenCost |
| Security | Zero-Trust Architecture |

## Failure Scenarios Tested

| Scenario | Expected Behavior | Result |
|----------|------------------|--------|
| Node failure under load | Auto-reschedule within 60s | Recovered in 20–46 seconds. SLO met. |
| Bad deployment | Readiness failure triggers rollback | Rollback completed in 32 seconds. Blast radius zero. |
| Traffic spike | HPA scales pods automatically | In progress |
| Secret rotation | Zero downtime credential rotation | In progress |

Variance in recovery time reflects real scheduler behavior under
different cluster states — not a controlled demo path.

## CI/CD Pipeline Stages

1. **Validate** — Manifest validation and quality gates
2. **Deploy Canary** — Single pod canary deployment
3. **Validate Canary** — Health check and readiness verification
4. **Rollback** — Automatic rollback on readiness failure
5. **Deploy Production** — Full promotion if canary passes

## Engineering Challenges Encountered

**Docker proxy missing in Codespaces**
Minikube requires docker-proxy to map ports but GitHub Codespaces
ships with moby-engine instead of docker-ce — the binary did not
exist. Extracted it manually from the docker-ce package without
installing the full package due to conflicts with existing components.
Undocumented edge case that took significant time to resolve.

**Memory constraints under full stack**
8GB RAM is insufficient when running a 3-node cluster, Prometheus,
Grafana, Vault, OpenCost, and a CI/CD pipeline simultaneously.
Grafana crashed mid-test due to memory limits. Required scaling down
components during installation then restoring full stack. Resource
management became the real engineering challenge inside the project.

**Git history rewrite**
Accidentally committed large binaries — kubectl, minikube, vault —
to the repository. GitHub rejected the push. Rewrote entire git
history three times using filter-branch to remove them. Now
.gitignore is the first file created on every new project.

## Key Engineering Insight

Kubernetes self-healing is not magic. It is reconciliation loops
running constantly at every layer of the stack.

The control plane does not detect failure and decide to act.
It simply keeps asking: does actual state match desired state?
When the answer is no — it corrects.

That single mental model explains HPA, rollbacks, readiness probes,
and node recovery. Same loop. Different levels.

## Current Status

🔧 Active development and testing
📊 Real failure behavior documented with measured recovery times
🔜 Next: Pod Disruption Budgets, topology spread constraints,
   live traffic continuity testing

## Author

Olamide Olalekan — Platform & DevSecOps Engineer
[LinkedIn](https://linkedin.com/in/olamide-olalekan-12138a265)
[GitHub](https://github.com/velrite)
