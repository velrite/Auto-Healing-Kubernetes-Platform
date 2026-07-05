# Auto-Healing Kubernetes Platform

A production-grade Kubernetes platform designed around failure as a
first-class concern — not an afterthought.

> **Environment note:** Built and tested on Minikube via GitHub Codespaces.
> The architecture, failure-handling patterns, and automation logic are
> directly portable to managed Kubernetes (EKS/AKS/GKE). Real-cloud
> deployment is the next phase — see Project 5 (Multi-Cloud Production
> Platform).

## Problem Statement

Most infrastructure is built to work under ideal conditions.
Production is not ideal.

Production means node loss, traffic spikes, bad deployments,
and cloud costs that grow faster than engineering output.

This platform is designed around those conditions from day one.

## Cluster

- 3-node Minikube cluster — Kubernetes v1.31.0
- prod-sim — control plane
- prod-sim-m02 — worker node
- prod-sim-m03 — worker node

## What This Platform Does

**Automated Failure Recovery**
- Detects node failure and reschedules pods automatically
- No manual intervention required for single node loss
- Reconciliation loop corrects actual vs desired state continuously
- Recovery validated: 20 seconds

**Horizontal Pod Autoscaling**
- HPA configured on api-service (CPU threshold 60%, memory 70%)
- HPA configured on frontend (CPU threshold 65%)
- Scales from minimum 2 pods to maximum 8 pods automatically
- Load tested with synthetic traffic and validated end to end

**Deployment Safety**
- 5-stage GitHub Actions CI/CD pipeline with enforced quality gates
- Canary deployments with traffic splitting
- Automated rollback triggered by pod readiness failure
- Zero static credentials via HashiCorp Vault dynamic secrets

**Observability**
- Golden Signals monitored per service
- 36 Prometheus alert rules focused on SLO-impacting conditions
- Alerting before issues become incidents

**Cost Visibility (FinOps)**
- Per-namespace and per-service cost breakdown via OpenCost
- Cost labels applied per service, team, and environment
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
| Progressive Delivery | HPA + Canary Deployments |

## Failure Scenarios Tested

| Scenario | Result | Numbers |
|----------|--------|---------|
| Node failure | SLO MET | Recovered in 20 seconds. Zero human intervention. |
| Bad deployment | SLO MET | Rollback in 32 seconds. Blast radius zero. |
| Traffic spike HPA | PASSED | Scaled from 2 to 8 pods. CPU hit 86%. Auto scale down after load. |
| Secret rotation | PASSED | Version 1 to Version 2 rotated. App running throughout. Zero downtime. |

## Test Results

### Node Failure Recovery
- Node killed: prod-sim-m02
- Pods rescheduled to: prod-sim-m03 automatically
- Recovery time: 20 seconds
- Human intervention required: zero
- Status: SLO MET

### Bad Deployment Rollback
- Bad image injected: kennethreitz/httpbin:this-tag-does-not-exist
- Old pods kept serving traffic throughout
- Blast radius: 0 pods affected
- Rollback time: 32 seconds
- Method: kubectl rollout undo — previous ReplicaSet promoted
- Status: SLO MET

### HPA Traffic Spike Test
- Load generators: 3 parallel busybox pods generating synthetic load
- Pod count before load: 2 pods, CPU 4%
- Peak pod count during load: 8 pods, CPU 86%
- Scale up triggered at: CPU above 60% threshold
- Scale down: automatic after load removed, CPU dropped to 2%
- Final pod count after scale down: 2 pods
- Status: PASSED — zero human intervention

### Vault Secret Rotation Test
- Secrets engine: HashiCorp Vault KV v2
- Initial secret: version 1 written successfully
- Rotation: version 2 written with new credentials
- App pods during rotation: all Running, zero restarts
- Zero downtime: confirmed
- Status: PASSED

## CI/CD Pipeline Stages

1. Validate — Manifest validation and quality gates
2. Deploy Canary — Single pod canary deployment
3. Validate Canary — Health check and readiness verification
4. Rollback — Automatic rollback on readiness failure
5. Deploy Production — Full promotion if canary passes

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

## Author

Olamide Olalekan — Platform and DevSecOps Engineer
LinkedIn: https://linkedin.com/in/olamide-olalekan-12138a265
GitHub: https://github.com/velrite
