# Auto-Healing Kubernetes Platform

A production-grade Kubernetes platform built around failure as a first-class concern.
Every component exists because of a specific failure mode it prevents.

**Author:** Olamide Olalekan — Platform & DevSecOps Engineer
**GitHub:** [github.com/velrite](https://github.com/velrite)
**LinkedIn:** [linkedin.com/in/olamide-olalekan-12138a265](https://linkedin.com/in/olamide-olalekan-12138a265)
**Email:** velrite.tech@gmail.com

---

## What This Is

A self-healing Kubernetes platform that recovers from node loss, scales under
traffic spikes, rolls back bad deployments, and manages secrets dynamically —
all without human intervention. Every failure scenario was tested live with
real measured results.

---

## Proven Results

| Test | Result | Time | Human Intervention |
|------|--------|------|--------------------|
| Node failure recovery | ✅ SLO MET | 20 seconds | Zero |
| Bad deployment rollback | ✅ SLO MET | 32 seconds | Zero |
| HPA traffic spike | ✅ PASSED | 2 → 8 pods at CPU 86% | Zero |
| Vault secret rotation | ✅ PASSED | Zero downtime | Zero |

All results from real terminal output. See [docs/TESTING_AND_VALIDATION.md](docs/TESTING_AND_VALIDATION.md).

---

## Cluster

```
3-node Minikube cluster — Kubernetes v1.31.0 — GitHub Codespaces

prod-sim        control-plane   192.168.49.2
prod-sim-m02    worker          192.168.49.3
prod-sim-m03    worker          192.168.49.4
```

[SCREENSHOT: kubectl get nodes showing all 3 nodes Ready]

---

## Architecture

```
                    GitHub Actions CI/CD
                    validate → canary → validate-canary
                    → rollback (on failure)
                    → deploy-production (on success)
                              │
                    ┌─────────▼──────────────────┐
                    │  Minikube Cluster (3 nodes)  │
                    │  Kubernetes v1.31.0          │
                    │                              │
                    │  namespace: microservices    │
                    │    api-service  (HPA 2-8)    │
                    │    frontend     (HPA 2-6)    │
                    │    postgres-db              │
                    │                              │
                    │  namespace: monitoring       │
                    │    Prometheus  (36 rules)    │
                    │    Grafana  (Golden Signals) │
                    │    Alertmanager              │
                    │                              │
                    │  namespace: vault            │
                    │    HashiCorp Vault           │
                    │    KV v2 + Database engine   │
                    │                              │
                    │  namespace: opencost         │
                    │    OpenCost                  │
                    │    Cost per service/team     │
                    └──────────────────────────────┘
```

---

## Tech Stack

| Layer | Technology | Why |
|-------|------------|-----|
| Orchestration | Kubernetes v1.31.0 | Reconciliation loops handle failure automatically |
| Cluster | Minikube 3-node | Free. Identical behavior to production k8s |
| CI/CD | GitHub Actions | 5-stage pipeline with auto-rollback |
| Secrets | HashiCorp Vault | Dynamic credentials. No static passwords |
| Monitoring | Prometheus + Grafana | 36 alert rules. Golden Signals dashboard |
| Cost | OpenCost | Real-time cost per service and namespace |
| Environment | GitHub Codespaces | Free 60hrs/month. 8GB RAM |

---

## What Was Built

### Microservices (namespace: microservices)
- api-service — nginx:alpine — 2 replicas — HPA min 2 max 8 — CPU threshold 60% memory 70%
- frontend — nginx:alpine — 2 replicas — HPA min 2 max 6 — CPU threshold 65%
- postgres-db — postgres:14-alpine — credentials loaded from Kubernetes secret
- LimitRange — default CPU 200m memory 128Mi per container
- ResourceQuota — max 20 pods, CPU 8 cores, memory 8Gi per namespace

### Monitoring (namespace: monitoring)
- Prometheus with 36 alert rules — PodCrashLooping, PodNotReady, HighMemory, HighCPU, HighErrorRate, NodeDown
- Grafana with Golden Signals dashboard — Traffic, Error Rate, Latency P99, Saturation
- Alert rules applied from monitoring/alert-rules.yaml

### Security (namespace: vault)
- HashiCorp Vault installed and initialized
- Vault unsealed with 3 of 5 keys
- Kubernetes auth enabled
- Database secrets engine configured with api-service-role (1h TTL)
- Dynamic credentials generated — two different passwords proved on live test
- KV v2 secrets engine — rotation from version 1 to version 2 tested
- Zero static credentials — pod describe returns nothing for password grep

### FinOps (namespace: opencost)
- OpenCost installed — confirmed 2/2 Running
- Cost labels on all deployments — team, cost-center, environment
- Cost API returning real data confirmed via curl
- OpenCost replaced Kubecost which failed with permission errors on Codespace

### CI/CD
- 5-stage GitHub Actions pipeline — validate, deploy-canary, validate-canary, rollback, deploy-production
- Pipeline confirmed green — all stages passing
- Canary health check monitors restart count over 5 minutes
- Auto-rollback fires on_failure — no human required

---

## Quick Start

```bash
# Start Docker and cluster
sudo nohup dockerd &
sleep 10
minikube start --profile=prod-sim --nodes=3 \
  --driver=docker --cpus=2 --memory=2000mb \
  --kubernetes-version=v1.31.0 --force

# Deploy
kubectl create namespace microservices
kubectl create secret generic postgres-secret \
  --from-literal=POSTGRES_PASSWORD=apppassword \
  --from-literal=POSTGRES_USER=appuser \
  --from-literal=POSTGRES_DB=appdb \
  -n microservices
kubectl apply -f manifests/
kubectl apply -f database.yaml
kubectl get pods -n microservices
```

See [docs/RUNBOOK.md](docs/RUNBOOK.md) for full operating procedures.

---

## Documentation

| File | Contents |
|------|----------|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Cluster design, namespaces, components, reconciliation model |
| [TESTING_AND_VALIDATION.md](docs/TESTING_AND_VALIDATION.md) | All 4 tests with real command output and numbers |
| [SECURITY.md](docs/SECURITY.md) | Vault setup, dynamic secrets, zero credential proof |
| [INCIDENTS.md](docs/INCIDENTS.md) | 5 real incidents encountered — root cause and fix |
| [ADR.md](docs/ADR.md) | Every architectural decision with alternatives rejected |
| [RUNBOOK.md](docs/RUNBOOK.md) | How to start, operate, and test the platform |
| [GAPS.md](docs/GAPS.md) | What was not built and what building it would require |
| [CAPACITY_AND_COST.md](docs/CAPACITY_AND_COST.md) | Resource usage, HPA config, OpenCost results |

---

## Related Projects

- [Project 2 — Terraform Kubernetes Platform](https://github.com/velrite/Terraform-Kubernetes-Platform) — same platform rebuilt as code
- [Project 3 — GitOps ArgoCD Platform](https://github.com/velrite/gitops-argocd-platform) — GitOps deployment automation
