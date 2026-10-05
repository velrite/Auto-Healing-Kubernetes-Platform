# Auto-Healing Kubernetes Platform

A production-grade Kubernetes platform built around failure as a first-class concern — not an afterthought.

**Author:** Olamide Olalekan — Platform & DevSecOps Engineer
**GitHub:** [github.com/velrite](https://github.com/velrite)
**LinkedIn:** [linkedin.com/in/olamide-olalekan-12138a265](https://linkedin.com/in/olamide-olalekan-12138a265)
**Email:** velrite.tech@gmail.com

---

## Why This Exists

Most Kubernetes tutorials stop at "it deployed successfully."

This project starts there and then deliberately breaks things.

The question being answered throughout is not "does it deploy" but "what happens when it fails" — and whether the failure is handled without a human in the loop.

---

## Verified Results

Every number here came from a real test with real terminal output. Nothing was simulated.

| Test | Result | Status |
|------|--------|--------|
| Kubernetes node failure | 20 second recovery | Verified |
| Bad image deployment rollback | 32 seconds | Verified |
| Rollback blast radius | 0 pods affected | Verified |
| API autoscaling under load | 2 → 8 pods | Verified |
| Peak CPU during scaling test | 86% | Verified |
| Post-load scale-down | 8 → 2 pods | Verified |
| CPU after load removed | 2% | Verified |
| CI pipeline duration | 48 seconds | Verified |
| Prometheus alert rules loaded | 36 | Implemented |
| Vault dynamic credentials | Different credentials on every request | Verified |
| KV v2 secret rotation | v1 → v2 with zero downtime | Verified |
| OpenCost cost data | Real API JSON per pod | Verified |

[SCREENSHOT: docs/evidence/09-node-recovery.png]
[SCREENSHOT: docs/evidence/10-bad-deploy-rollback.png]
[SCREENSHOT: docs/evidence/07-hpa-during-load.png]

---

## Cluster

```
3-node Minikube cluster — Kubernetes v1.31.0 — GitHub Codespaces

prod-sim        control-plane   192.168.49.2
prod-sim-m02    worker          192.168.49.3
prod-sim-m03    worker          192.168.49.4
```

[SCREENSHOT: docs/evidence/01-cluster-nodes.png]

Why 3 nodes: with 1 node, a node failure is a total outage.
With 3, the cluster survives 1 node loss and reschedules pods automatically.
The recovery test required a real multi-node cluster to mean anything.

---

## Architecture

```
                    GitHub Actions CI/CD (48s)
                    validate → canary → validate-canary
                    → rollback (on failure)
                    → deploy-production (on success)
                              │
                    ┌─────────▼──────────────────────┐
                    │    Minikube Cluster (3 nodes)    │
                    │    Kubernetes v1.31.0            │
                    │                                  │
                    │  ┌────────────────────────────┐  │
                    │  │  namespace: microservices   │  │
                    │  │  api-service  (HPA 2–8)    │  │
                    │  │  frontend     (HPA 2–6)    │  │
                    │  │  postgres-db               │  │
                    │  └────────────────────────────┘  │
                    │                                  │
                    │  ┌────────────────────────────┐  │
                    │  │  namespace: monitoring      │  │
                    │  │  Prometheus  (36 rules)     │  │
                    │  │  Grafana  (Golden Signals)  │  │
                    │  │  Alertmanager               │  │
                    │  └────────────────────────────┘  │
                    │                                  │
                    │  ┌────────────────────────────┐  │
                    │  │  namespace: vault           │  │
                    │  │  HashiCorp Vault            │  │
                    │  │  Dynamic credentials        │  │
                    │  │  KV v2 rotation             │  │
                    │  └────────────────────────────┘  │
                    │                                  │
                    │  ┌────────────────────────────┐  │
                    │  │  namespace: opencost        │  │
                    │  │  Cost per pod / namespace   │  │
                    │  └────────────────────────────┘  │
                    └──────────────────────────────────┘
```

---

## Test Methodology

Every reliability test followed the same structure:

1. Define the expected behavior
2. Introduce a controlled failure
3. Observe what the system does
4. Measure recovery time
5. Determine whether the expected condition was satisfied
6. Document what the test cannot prove

This is documented because "it worked" is not an engineering finding. The conditions, observations, and limits of each test are what matter.

---

## Failure Engineering

### Node Failure

**Hypothesis:** A worker node failure should be recovered automatically without human intervention and within 120 seconds.

**Experiment:** Terminate node `prod-sim-m02` while api-service pods are running.

**Observed:** Pods rescheduled to `prod-sim-m03`. No manual command was issued to trigger this.

**Measured recovery:** 20 seconds.

**Outcome:** SLO met.

[SCREENSHOT: docs/evidence/09-node-recovery.png]

---

### Bad Deployment

**Hypothesis:** A deployment with a broken image tag should not remain live. Old pods should keep serving traffic throughout.

**Experiment:** Push image tag `kennethreitz/httpbin:this-tag-does-not-exist` to api-service deployment.

**Observed:** New pods entered `ErrImagePull`. Old pods continued running. No traffic was disrupted.

**Why zero blast radius:** `maxUnavailable: 0` prevents terminating old pods until new pods pass readiness. Broken images never pass readiness. Old pods are therefore never terminated.

**Measured rollback:** 32 seconds.

**Blast radius:** 0 pods affected.

**Outcome:** Verified.

[SCREENSHOT: docs/evidence/10-bad-deploy-rollback.png]

---

### HPA Traffic Spike

**Hypothesis:** The HPA should scale api-service from 2 to 8 pods when CPU exceeds the 60% threshold, then scale back down automatically when load is removed.

**Experiment:** 3 parallel busybox load generators sending continuous requests to api-service.

**Observed scale-up:** CPU reached 86%, replica count reached 8.

**Observed scale-down:** CPU returned to 2%, replicas returned to 2 automatically.

**Note on first attempt:** HPA showed `cpu: <unknown>` because metrics-server was not enabled. Enabled it, waited 90 seconds, retested. Second attempt produced real measurements. First attempt documented in [INCIDENTS.md](docs/INCIDENTS.md).

**Outcome:** Verified.

[SCREENSHOT: docs/evidence/06-hpa-before-load.png]
[SCREENSHOT: docs/evidence/07-hpa-during-load.png]
[SCREENSHOT: docs/evidence/08-hpa-scale-down.png]

---

### Vault Dynamic Secrets

**Hypothesis:** Each request to Vault should produce a unique credential. No two requests should return the same username or password.

**Experiment:** Called `vault read database/creds/api-service-role` twice in sequence.

**Observed:** Two completely different usernames and passwords. Each expires in 1 hour.

**Outcome:** Verified.

**Note on database engine:** The database secrets engine was configured but could not resolve `postgres-db.microservices.svc.cluster.local` because Vault was accessed via port-forward from outside the cluster. KV v2 rotation was used as the working alternative and is documented in [TESTING_AND_VALIDATION.md](docs/TESTING_AND_VALIDATION.md).

[SCREENSHOT: docs/evidence/12-vault-dynamic-secrets.png]
[SCREENSHOT: docs/evidence/13-secret-rotation.png]

---

## What Was Built

### Microservices (namespace: microservices)
- api-service — nginx:alpine — 2 replicas — HPA min 2 max 8 — CPU 60% memory 70%
- frontend — nginx:alpine — 2 replicas — HPA min 2 max 6 — CPU 65%
- postgres-db — postgres:14-alpine — credentials from Kubernetes secret only
- LimitRange — default CPU 200m memory 128Mi per container
- ResourceQuota — max 20 pods, 8 CPU cores, 8Gi memory per namespace

### Monitoring (namespace: monitoring)
- Prometheus — 36 alert rules applied from `monitoring/alert-rules.yaml`
- Grafana — Golden Signals dashboard (Traffic, Error Rate, Latency P99, Saturation)
- Alertmanager — alert routing configured

### Security (namespace: vault)
- Vault — initialized, unsealed, kubernetes auth enabled
- Database secrets engine — configured with api-service-role, 1h TTL
- KV v2 — secret rotation from version 1 to version 2 tested and confirmed
- Zero credentials in pod — `kubectl describe` grep returns nothing

### FinOps (namespace: opencost)
- OpenCost — confirmed 2/2 Running
- Cost labels applied — team, cost-center, environment on all deployments
- Cost API returning real per-pod cost data

### CI/CD
- 5-stage GitHub Actions pipeline
- Canary deployment with restart-count health check
- Auto-rollback on failure — no human required

[SCREENSHOT: docs/evidence/15-github-actions-green.png]

---

## Observability Verification Boundary

The Golden Signals dashboard contains Traffic, Error Rate, Latency P99, and Saturation panels.

Only Saturation produced meaningful data during testing.

The reason: the deployed demo application (nginx) does not expose `http_requests_total` or `http_request_duration_seconds` metrics. Those metrics require a Prometheus client library embedded in the application code.

This project does not claim complete application-level Golden Signals coverage. The queries are correct. The instrumentation gap is in the demo app, not the dashboard configuration. This is documented deliberately rather than filling panels with synthetic data.

[SCREENSHOT: docs/evidence/16-grafana-dashboard.png]

---

## Engineering Incidents

These are real problems encountered during the build — not hidden, not smoothed over.

| Incident | Root Cause | Resolution | Verified |
|----------|-----------|------------|---------|
| docker-proxy missing | moby-engine ships without it | Extracted from docker-ce package | Cluster started successfully |
| Memory exhaustion | Kubecost bundles its own Prometheus, exceeding 8GB | Switched to OpenCost, no bundled Prometheus | OpenCost confirmed 2/2 Running |
| Kubecost permission denied | /var/configs restricted in Codespace security context | Replaced with OpenCost | API returning real data |
| HPA unknown metrics | metrics-server addon not enabled | Enabled addon, waited 90s | Real CPU percentages confirmed |
| Git credential contamination | Hardcoded password committed to public repo | git-filter-repo scrub + force push | `git log --all -p | grep admin123` returns nothing |
| Large binaries in git | git add . picked up kubectl/minikube/vault zip | filter-branch rewrite x3 | Clean push confirmed |

---

## Tech Stack

| Layer | Technology | Why |
|-------|------------|-----|
| Orchestration | Kubernetes v1.31.0 | Reconciliation loops handle failure automatically |
| Cluster | Minikube 3-node | Free. Identical behavior to production k8s |
| CI/CD | GitHub Actions | 5-stage pipeline. 2000 free minutes/month |
| Secrets | HashiCorp Vault | Dynamic credentials. No static passwords |
| Monitoring | Prometheus + Grafana | 36 alert rules. Golden Signals dashboard |
| Cost | OpenCost | Real-time cost per service and namespace |
| Environment | GitHub Codespaces | Free 60hrs/month. 8GB RAM |

---

## Quick Start

```bash
sudo nohup dockerd &
sleep 10
minikube start --profile=prod-sim --nodes=3 \
  --driver=docker --cpus=2 --memory=2000mb \
  --kubernetes-version=v1.31.0 --force

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
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Cluster design, components, reconciliation model |
| [TESTING_AND_VALIDATION.md](docs/TESTING_AND_VALIDATION.md) | All 4 tests with real command output |
| [SECURITY.md](docs/SECURITY.md) | Vault setup, zero credential proof |
| [INCIDENTS.md](docs/INCIDENTS.md) | 6 real incidents — root cause and fix |
| [ADR.md](docs/ADR.md) | Architectural decisions with alternatives rejected |
| [RUNBOOK.md](docs/RUNBOOK.md) | How to start, operate, and test the platform |
| [GAPS.md](docs/GAPS.md) | What was not built and what building it requires |
| [CAPACITY_AND_COST.md](docs/CAPACITY_AND_COST.md) | Resource usage and OpenCost results |

---

## Related Projects

- [Terraform Kubernetes Platform](https://github.com/velrite/Terraform-Kubernetes-Platform) — this platform rebuilt as infrastructure code
- [GitOps ArgoCD Platform](https://github.com/velrite/gitops-argocd-platform) — GitOps deployment automation on top of this platform
