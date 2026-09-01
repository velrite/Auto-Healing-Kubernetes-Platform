# Gaps and Honest Limits

---

## Application Metrics — Traffic, Error Rate, Latency

Golden Signals dashboard is configured with correct PromQL queries.
Only Saturation shows data because nginx does not expose
http_requests_total or http_request_duration_seconds.

What building it requires:
- Add prometheus_client library to each service
- Expose /metrics endpoint
- Add pod annotations: prometheus.io/scrape: "true"

---

## Dynamic Database Credentials via Vault Database Engine

Vault database secrets engine was configured and role created.
Dynamic credentials were generated twice and proved unique.
However port-forward from outside the cluster cannot resolve
postgres-db.microservices.svc.cluster.local DNS.
KV v2 rotation was used as the working alternative.

What full dynamic rotation requires:
- Vault Agent Injector running as sidecar inside cluster
- Pod annotations to request secret injection
- Vault resolving postgres via cluster-internal DNS

---

## Pod Disruption Budgets

Not applied. During node failure all pods on affected node terminated
simultaneously. A PDB would guarantee minimum availability.

---

## Network Policies

Not applied. All pods can reach all other pods within cluster.
Zero-trust networking would require explicit allow rules per service.

---

## Persistent Grafana Dashboards

Golden Signals dashboard was recreated manually after Grafana restarts.
No persistent volume configured. Dashboard lost on pod restart.

Fix: store dashboard JSON as ConfigMap with grafana sidecar annotation.

---

## Image Signing

No Cosign signing. Any image can be deployed without verification.
