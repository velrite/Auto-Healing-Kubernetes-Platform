# Capacity and Cost

## Cluster Resource Allocation

### Node Resources
Each Minikube node allocated:
- CPU: 2 cores
- Memory: 2000MB

Total cluster: 6 cores, 6GB RAM allocated to nodes.
Host machine: 8GB RAM (GitHub Codespace).

### Namespace Resource Usage (approximate at idle)

| Namespace | CPU Request | Memory Request | Purpose |
|-----------|-------------|----------------|---------|
| microservices | 175m | 224Mi | Application workloads |
| monitoring | 335m | 640Mi | Prometheus, Grafana, Alertmanager |
| vault | 50m | 128Mi | HashiCorp Vault |
| opencost | 10m | 64Mi | Cost visibility |
| kube-system | ~300m | ~512Mi | Kubernetes system components |

---

## HPA Configuration

| Deployment | Min Replicas | Max Replicas | CPU Threshold | Memory Threshold |
|------------|-------------|--------------|---------------|-----------------|
| api-service | 2 | 8 | 60% | 70% |
| frontend | 2 | 6 | 65% | — |

**Load test results:**
- 3 parallel load generators pushed CPU to 86%
- HPA scaled from 2 to 8 pods (maximum)
- Additional scaling not possible — already at maxReplicas
- CPU dropped to 2% after load removed
- Scale down automatic — pods terminated over approximately 5 minutes

---

## Cost Visibility (OpenCost)

OpenCost confirmed returning real cost data per pod:

Sample allocation data from test run:
```json
{
  "prod-sim/prod-sim-m03/microservices/api-service/.../api-service": {
    "cpuCores": 0.05,
    "cpuCost": 0.00015,
    "ramBytes": 67108864,
    "ramCost": 0.00003,
    "totalCost": 0.00018
  }
}
```

Cost labels applied to all deployments:
- api-service: team=backend, cost-center=platform, environment=production
- frontend: team=frontend, cost-center=product, environment=production
- postgres-db: team=data, cost-center=platform, environment=production

**Infrastructure cost:**
GitHub Codespaces free tier used throughout.
Zero cloud spend for this project.
All tools open source and self-hosted.

