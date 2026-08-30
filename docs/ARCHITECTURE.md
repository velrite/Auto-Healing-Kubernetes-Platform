# Architecture

## Cluster Design

3-node Minikube cluster running Kubernetes v1.31.0 on GitHub Codespaces.

```
Node            Role            IP              Workloads
──────────────────────────────────────────────────────────
prod-sim        control-plane   192.168.49.2    etcd, API server, scheduler
prod-sim-m02    worker          192.168.49.3    application pods
prod-sim-m03    worker          192.168.49.4    application pods
```

**Why 3 nodes?**
With 1 node, node failure means total outage.
With 3 nodes, 1 node can fail and the cluster reschedules to the remaining 2.
That is the minimum for meaningful high availability testing.

**Why Minikube over kind?**
See [ADR-001](ADR.md#adr-001--minikube-over-kind).

---

## Namespace Design

| Namespace | Purpose | Key Components |
|-----------|---------|----------------|
| microservices | Application workloads | api-service, frontend, postgres-db |
| monitoring | Observability stack | Prometheus, Grafana, Alertmanager |
| vault | Secrets management | HashiCorp Vault |
| opencost | Cost visibility | OpenCost, cost API |

Namespace isolation prevents one component's failure from cascading.
If monitoring crashes, microservices keep serving.

---

## Application Layer (namespace: microservices)

### api-service
- Image: nginx:alpine (demo — would be real API in production)
- Replicas: 2 minimum, 8 maximum
- HPA: scale up when CPU > 60% OR memory > 70%
- Service type: ClusterIP (internal only)
- Resources: 50m CPU request, 200m limit / 64Mi RAM request, 128Mi limit

### frontend
- Image: nginx:alpine (demo)
- Replicas: 2 minimum, 6 maximum
- HPA: scale up when CPU > 65%
- Service type: NodePort on 30421 (external access)
- Resources: 25m CPU request, 100m limit / 32Mi RAM request, 64Mi limit

### postgres-db
- Image: postgres:14-alpine
- Replicas: 1 (single instance — multi-replica postgres requires StatefulSet + PVC)
- Credentials: loaded from kubernetes secret, never hardcoded
- Resources: standard defaults

---

## Monitoring Stack (namespace: monitoring)

### Prometheus
- Scrapes metrics from every pod every 30 seconds
- 36 alert rules covering:
  - PodCrashLooping — fires when restart rate > 0.05/minute over 5 minutes
  - PodNotReady — fires when pod not ready for > 5 minutes
  - HighMemoryUsage — fires when container memory > 85% of limit for 10 minutes
  - HighCPUUsage — fires when container CPU > 80% of limit for 10 minutes
  - HighErrorRate — fires when HTTP 5xx rate > 1% for 5 minutes
  - NodeDown — fires when node unreachable for > 2 minutes

### Grafana — Golden Signals Dashboard
Four panels corresponding to Google SRE's Four Golden Signals:

| Signal | PromQL Query | What It Tells You |
|--------|-------------|-------------------|
| Traffic | `sum(rate(http_requests_total{namespace="microservices"}[5m])) by (service)` | How busy is the service |
| Error Rate | `sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))` | Is it failing |
| Latency P99 | `histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service))` | How slow for the worst 1% |
| Saturation | `sum(rate(container_cpu_usage_seconds_total{namespace="microservices"}[5m])) by (pod)` | How close to capacity |

Traffic, Error Rate, and Latency show no data because the demo app
does not expose http_requests_total metrics. See [GAPS.md](GAPS.md).
Saturation shows real data because Kubernetes exposes CPU metrics automatically.

---

## Secrets Management (namespace: vault)

HashiCorp Vault deployed in dev mode.

Secret flow:
```
Vault KV v2
  └── secret/api-service/db
        ├── version 1: password=initialpassword123
        └── version 2: password=rotatedpassword456 (rotated)
```

Application reads credentials from Kubernetes secret.
Secret rotation is versioned — previous version available for rollback.
Zero downtime rotation confirmed: app pods kept running throughout.

**Why not Vault database engine for dynamic postgres credentials?**
See [GAPS.md](GAPS.md#dynamic-database-credentials-via-vault-database-engine).

---

## Cost Visibility (namespace: opencost)

OpenCost deployed and confirmed returning real cost data via API.

Cost labels applied to all deployments:
```
cost-center: platform  (api-service, postgres-db)
cost-center: product   (frontend)
team: backend          (api-service)
team: frontend         (frontend)
team: data             (postgres-db)
environment: production
```

API confirmed working:
```bash
curl -s "http://localhost:9003/allocation?window=1d" | jq '.'
# Returns real cost data per pod per namespace
```

[SCREENSHOT: OpenCost API response showing cost per namespace]

---

## Reconciliation Model

The entire platform runs on one mental model:

```
Desired state (code/config) ──compare──► Actual state (cluster)
        ▲                                        │
        └──────────── if different ──────────────┘
                    correct automatically
```

This loop runs continuously at multiple levels simultaneously:
- kubelet ensures containers match their pod spec
- ReplicaSet controller ensures pod count matches replicas field
- HPA controller adjusts replicas to match CPU/memory thresholds
- Node controller marks nodes NotReady and triggers rescheduling

Recovery from node failure is not a special recovery mode.
It is the normal reconciliation loop detecting that actual pod count
is less than desired pod count and correcting it.

