# Architecture

## Cluster

3-node Minikube cluster on GitHub Codespaces.

```
Node            Role            IP              Resources
─────────────────────────────────────────────────────────
prod-sim        control-plane   192.168.49.2    2 CPU, 2GB RAM
prod-sim-m02    worker          192.168.49.3    2 CPU, 2GB RAM
prod-sim-m03    worker          192.168.49.4    2 CPU, 2GB RAM
```

Why 3 nodes: with 1 node, node failure means total outage.
With 3, the cluster survives 1 node loss and reschedules automatically.
That is the minimum to test meaningful high availability.

---

## Namespaces

| Namespace | Purpose |
|-----------|---------|
| microservices | Application workloads |
| monitoring | Prometheus, Grafana, Alertmanager |
| vault | HashiCorp Vault |
| opencost | OpenCost cost visibility |

Namespace isolation means one component crashing cannot cascade.
If monitoring exhausts memory, microservices keep serving.

---

## Application Layer

### api-service
- Image: nginx:alpine
- Replicas: 2 minimum, 8 maximum
- HPA: scales when CPU > 60% or memory > 70%
- Service: ClusterIP — internal only
- CPU request 50m / limit 200m
- Memory request 64Mi / limit 128Mi

### frontend
- Image: nginx:alpine
- Replicas: 2 minimum, 6 maximum
- HPA: scales when CPU > 65%
- Service: NodePort on 30421

### postgres-db
- Image: postgres:14-alpine
- Replicas: 1
- Credentials: loaded from kubernetes secret — never hardcoded

---

## Resource Management

LimitRange sets defaults for every container in microservices namespace.
ResourceQuota caps total consumption — max 20 pods, 8 CPU cores, 8Gi memory.
Without these, one runaway pod can consume all cluster resources.

HPA thresholds chosen conservatively for 8GB Codespace:
- api-service at 60% CPU because it needs headroom to handle spikes
- frontend at 65% CPU because it is stateless and cheaper to scale

---

## Monitoring

### Prometheus
Scrapes metrics from every pod every 30 seconds.
36 alert rules applied from monitoring/alert-rules.yaml.

Key alerts:
- PodCrashLooping — restart rate > 0.05/min over 5 minutes — severity critical
- PodNotReady — not ready for > 5 minutes — severity warning
- HighMemoryUsage — > 85% of limit for 10 minutes — severity warning
- HighCPUUsage — > 80% of limit for 10 minutes — severity warning
- HighErrorRate — HTTP 5xx > 1% for 5 minutes — severity critical
- NodeDown — unreachable for > 2 minutes — severity critical

### Grafana — Golden Signals Dashboard
Four panels covering the four signals Google SRE recommends:

| Signal | Query | Data |
|--------|-------|------|
| Traffic | rate(http_requests_total) by service | No data — nginx has no prometheus client |
| Error Rate | rate(http_requests_total{status=~"5.."}) | No data — same reason |
| Latency P99 | histogram_quantile(0.99, ...) | No data — same reason |
| Saturation | rate(container_cpu_usage_seconds_total) by pod | Real data — k8s exposes this automatically |

Traffic, Error Rate and Latency would show data with a real application
that exposes /metrics via a prometheus client library.
The queries are correct — the demo app does not emit those metrics.

---

## Secrets Management

### Vault Dynamic Credentials
Vault database secrets engine configured with api-service-role.
Credentials expire after 1 hour.
Running vault read twice produces two completely different credentials.
That is dynamic secrets working as designed.

### Vault KV v2
Secret versioning. Version 1 written, version 2 rotated.
Previous version retained — rollback without redeployment possible.

### Zero Static Credentials
```bash
kubectl describe pod -l app=api-service -n microservices | grep -i password
# Returns nothing
```

---

## Reconciliation Model

The platform runs on one mental model repeated at every layer:

```
Desired state ──compare──► Actual state
      ▲                          │
      └──── if different ────────┘
            correct automatically
```

- kubelet: ensures containers match pod spec
- ReplicaSet controller: ensures pod count matches replicas
- HPA controller: adjusts replicas to match CPU/memory thresholds
- Node controller: marks nodes NotReady and triggers rescheduling

Recovery from node failure is not a special mode.
It is the normal reconciliation loop correcting pod count.

---

## CI/CD Pipeline

5 stages via GitHub Actions:

```
1. validate        — kubectl dry-run all manifests
2. deploy-canary   — deploy 1 pod with new image
3. validate-canary — monitor restart count for 5 minutes
4. rollback        — fires on_failure — reverts to previous ReplicaSet
5. deploy-production — fires on_success — full rollout
```

Auto-rollback means a bad deployment never reaches production fully.
Old pods keep serving while canary is being evaluated.
