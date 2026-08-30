# Auto-Healing Kubernetes Platform

> A production-grade Kubernetes platform built around failure as a first-class concern — not an afterthought.

**Author:** Olamide Olalekan — Platform & DevSecOps Engineer
**GitHub:** [github.com/velrite](https://github.com/velrite)
**LinkedIn:** [linkedin.com/in/olamide-olalekan-12138a265](https://linkedin.com/in/olamide-olalekan-12138a265)
**Email:** velrite.tech@gmail.com

---

## The Problem This Solves

Most infrastructure is built to work under ideal conditions.
Production is not ideal.

Production means node loss at 3am, traffic spikes during a product launch,
a developer pushing a broken image tag, and cloud costs that silently grow
faster than engineering output.

This platform is built around those four conditions from day one.
Every component exists because of a specific failure mode it prevents.

---

## Proven Results

| Test | Outcome | Measured Time | Human Intervention |
|------|---------|--------------|-------------------|
| Node failure recovery | ✅ SLO MET | **20 seconds** | Zero |
| Bad deployment rollback | ✅ SLO MET | **32 seconds** | Zero |
| HPA traffic spike | ✅ PASSED | 2 → 8 pods at 86% CPU | Zero |
| Vault secret rotation | ✅ PASSED | Zero downtime | Zero |

> All results captured from real terminal output. Nothing simulated.
> See [docs/TESTING_AND_VALIDATION.md](docs/TESTING_AND_VALIDATION.md) for full command output.

---

## Architecture at a Glance

```
                        ┌─────────────────────────────┐
                        │   GitHub Actions CI/CD       │
                        │  validate → canary → rollback│
                        │  → production (48s pipeline) │
                        └────────────┬────────────────┘
                                     │
                        ┌────────────▼────────────────┐
                        │   Minikube Cluster (3 nodes) │
                        │   Kubernetes v1.31.0         │
                        │                              │
                        │  ┌──────────────────────┐   │
                        │  │ namespace: microservices│  │
                        │  │  api-service (HPA 2-8) │  │
                        │  │  frontend    (HPA 2-6) │  │
                        │  │  postgres-db           │  │
                        │  └──────────────────────┘   │
                        │                              │
                        │  ┌──────────────────────┐   │
                        │  │ namespace: monitoring  │  │
                        │  │  Prometheus (36 rules) │  │
                        │  │  Grafana (Golden Sig.) │  │
                        │  │  Alertmanager          │  │
                        │  └──────────────────────┘   │
                        │                              │
                        │  ┌──────────────────────┐   │
                        │  │ namespace: vault       │  │
                        │  │  HashiCorp Vault       │  │
                        │  │  Dynamic KV secrets    │  │
                        │  └──────────────────────┘   │
                        │                              │
                        │  ┌──────────────────────┐   │
                        │  │ namespace: opencost    │  │
                        │  │  Cost per namespace    │  │
                        │  │  Cost per service      │  │
                        │  └──────────────────────┘   │
                        └─────────────────────────────┘
```

---

## Tech Stack

| Layer | Technology | Why |
|-------|------------|-----|
| Container Orchestration | Kubernetes v1.31.0 | Industry standard. Reconciliation loops handle failure automatically. |
| Local Cluster | Minikube (3 nodes) | Free. Identical behavior to production k8s. |
| CI/CD | GitHub Actions | Already where the code lives. 2000 free minutes/month. |
| Secrets Management | HashiCorp Vault | Dynamic credentials. No static passwords anywhere. |
| Monitoring | Prometheus + Grafana | Industry standard. 36 alert rules. Golden Signals dashboard. |
| Cost Visibility | OpenCost | Real-time cost per service. Free and open source. |
| Environment | GitHub Codespaces | Free 60hrs/month. 8GB RAM. No local setup required. |

---

## Quick Start — Running This Yourself

### Prerequisites
- GitHub Codespace (or Ubuntu machine with 8GB+ RAM)
- kubectl, helm, minikube installed

### Start the cluster
```bash
sudo nohup dockerd &
sleep 10
minikube start --profile=prod-sim --nodes=3 \
  --driver=docker --cpus=2 --memory=2000mb \
  --kubernetes-version=v1.31.0 --force
kubectl get nodes
```

### Deploy everything
```bash
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

### Run the break-it tests
See [docs/RUNBOOK.md](docs/RUNBOOK.md) for step-by-step test commands.

---

## Documentation

| Document | What It Covers |
|----------|---------------|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Full system design, components, reconciliation model |
| [TESTING_AND_VALIDATION.md](docs/TESTING_AND_VALIDATION.md) | All 4 tests with real command output and numbers |
| [SECURITY.md](docs/SECURITY.md) | Vault setup, zero static credentials, git hygiene |
| [INCIDENTS.md](docs/INCIDENTS.md) | Real failures during the build — root cause and fix |
| [ADR.md](docs/ADR.md) | Every architectural decision with alternatives rejected |
| [RUNBOOK.md](docs/RUNBOOK.md) | How to start, operate, and test the platform |
| [GAPS.md](docs/GAPS.md) | What was not built and what building it would require |
| [CAPACITY_AND_COST.md](docs/CAPACITY_AND_COST.md) | Resource usage, cost data, FinOps results |

---

## CI/CD Pipeline

```
Push to main
  └── validate        — kubectl dry-run all manifests
  └── deploy-canary   — 1 pod with new image
  └── validate-canary — restart count check over 5 min
  └── rollback        — fires on_failure, reverts ReplicaSet
  └── deploy-production — fires on_success, full rollout
```

Pipeline completes in ~48 seconds.
Every stage must pass before the next runs.
Rollback is automatic — no human required.

[SCREENSHOT: GitHub Actions showing all 5 stages green with timing]

---

## The Key Insight

Kubernetes self-healing is not magic. It is one loop running constantly:

```
Does actual state match desired state?
  YES → do nothing
  NO  → correct it
```

That loop runs at every layer simultaneously:
- Kubernetes reconciles pods to match Deployments
- HPA reconciles replica count to match CPU thresholds
- ArgoCD (Project 3) reconciles cluster state to match Git

Same pattern. Different levels. Understanding this one thing
makes every other Kubernetes behavior predictable.

