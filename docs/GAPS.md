# Gaps and Honest Limits

What was not built, stated plainly with what building it properly
would require. A documented gap is more useful than a faked checkbox.

---

## Real Application Metrics (Traffic, Error Rate, Latency)

**What was built:**
Golden Signals dashboard configured with correct PromQL queries
for all four signals.

**What is missing:**
Three of the four signals show no data. The demo app (nginx) does not
expose http_requests_total or http_request_duration_seconds metrics.
Only Saturation shows data because Kubernetes exposes CPU metrics
automatically for all containers.

**What building it properly requires:**
- Add prometheus_client library to each service
- Expose /metrics endpoint on each service
- Add pod annotations: prometheus.io/scrape: "true", prometheus.io/port: "8080"
- Prometheus will automatically scrape the endpoint

With a real application (Python Flask, Node.js Express, Go) this is
a 20-line addition per service. Using nginx as a demo app bypasses
the need for application code but also means no application metrics.

---

## Dynamic Database Credentials via Vault Database Engine

**What was built:**
Vault database secrets engine configured and database role created.
KV v2 secret rotation tested and validated with zero downtime.

**What is missing:**
Vault database engine cannot connect to postgres-db because Vault
is accessed via port-forward from outside the cluster, and the
port-forward cannot resolve postgres-db.microservices.svc.cluster.local.

**What building it properly requires:**
- Run Vault inside the cluster (not accessed via external port-forward)
- Use Vault Agent Injector — a sidecar that automatically injects
  secrets into pod filesystems without application code changes
- Pod annotations to request secret injection:
  ```
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/role: "api-service"
  vault.hashicorp.com/agent-inject-secret-db-creds: "database/creds/api-service-role"
  ```

---

## Pod Disruption Budgets

**What is missing:**
No PDBs configured. During node failure, all pods on the affected node
terminated simultaneously. A PDB guarantees minimum availability during
voluntary disruptions (drains, upgrades).

**What building it requires:**
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: api-service-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: api-service
```

---

## Network Policies

**What is missing:**
No network policies applied. All pods can communicate with all other pods
within the cluster. Zero-trust networking would require explicit allow rules.

**What building it requires:**
Default deny all policy plus explicit allow rules per service:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
```

Then explicit allow rules for legitimate traffic paths.

---

## Persistent Grafana Dashboards

**What is missing:**
Golden Signals dashboard was recreated manually after Grafana restarts
because no persistent volume was configured. Dashboard state is lost
on pod restart.

**What building it requires:**
Store dashboard JSON as a ConfigMap with the grafana.sidecar.dashboards
annotation. Grafana sidecar automatically loads dashboards from ConfigMaps.

---

## Image Signing and Verification

**What is missing:**
No Cosign image signing. Any image can be deployed without verification
of its source or integrity.

**What building it requires:**
- Sign images with Cosign during CI build
- Install Sigstore policy controller in cluster
- Configure ClusterImagePolicy requiring valid Cosign signatures
- Unsigned images rejected at admission

