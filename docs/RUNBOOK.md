# Runbook

Step-by-step operating procedures for this platform.
Written so any engineer can follow without prior context.

---

## Starting the Platform After Codespace Restart

Every time a Codespace restarts, Docker and Minikube must be restarted.
The cluster state (pods, deployments) is preserved in Minikube.

**Step 1 — Fix docker-proxy (required on every new Codespace):**
```bash
# Only needed if /usr/libexec/docker/docker-proxy does not exist
ls /usr/libexec/docker/docker-proxy || (
  cd /tmp
  apt download docker-ce -y
  dpkg -x docker-ce_*.deb docker-extract
  sudo mkdir -p /usr/libexec/docker
  sudo cp docker-extract/usr/bin/docker-proxy /usr/libexec/docker/
  sudo chmod +x /usr/libexec/docker/docker-proxy
)
```

**Step 2 — Start Docker:**
```bash
sudo nohup dockerd &
sleep 10
docker ps  # Should show minikube containers
```

**Step 3 — Start Minikube:**
```bash
minikube start --profile=prod-sim --force
```

**Step 4 — Verify cluster:**
```bash
kubectl get nodes
# Expected: 3 nodes all Ready
kubectl get pods --all-namespaces | grep -v Completed
# Expected: all pods Running
```

**Step 5 — Restore port-forwards:**
```bash
kubectl port-forward svc/prometheus-kube-prometheus-prometheus \
  -n monitoring 9090:9090 &
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80 &
kubectl port-forward svc/opencost -n opencost 9003:9003 &
kubectl port-forward svc/vault -n vault 8200:8200 &
export VAULT_ADDR='http://127.0.0.1:8200'
vault login root
```

---

## Accessing Services

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | http://localhost:3000 | admin / get from vault secret |
| Prometheus | http://localhost:9090 | none required |
| OpenCost | http://localhost:9003 | none required |
| Vault UI | http://localhost:8200 | token: root (dev mode) |

---

## Running Break-It Tests

### Node Failure Test
```bash
# Step 1: Record start time and kill node
KILL_TIME=$(date +%s)
minikube node stop prod-sim-m02 --profile=prod-sim

# Step 2: Watch pods reschedule
kubectl get pods -n microservices -w

# Step 3: Measure recovery
kubectl wait --for=condition=ready pod -l app=api-service \
  -n microservices --timeout=5m
RECOVERY_TIME=$(date +%s)
echo "Recovery: $((RECOVERY_TIME - KILL_TIME)) seconds"

# Step 4: Restore node
minikube node start prod-sim-m02 --profile=prod-sim
```

### Bad Deployment Test
```bash
# Step 1: Inject bad image
INCIDENT_START=$(date +%s)
kubectl set image deployment/api-service \
  api-service=kennethreitz/httpbin:this-tag-does-not-exist \
  -n microservices

# Step 2: Watch pods
kubectl get pods -n microservices

# Step 3: Roll back
kubectl rollout undo deployment/api-service -n microservices
kubectl rollout status deployment/api-service -n microservices --timeout=3m
RECOVERY_TIME=$(date +%s)
echo "Rollback: $((RECOVERY_TIME - INCIDENT_START)) seconds"
```

### HPA Load Test
```bash
# Step 1: Baseline
kubectl get hpa -n microservices
kubectl get pods -n microservices | grep api-service | wc -l

# Step 2: Generate load
kubectl run load-generator --image=busybox --restart=Never \
  -n microservices -- /bin/sh -c \
  "while true; do wget -q -O- http://api-service.microservices.svc.cluster.local; done"
kubectl run load-generator-2 --image=busybox --restart=Never \
  -n microservices -- /bin/sh -c \
  "while true; do wget -q -O- http://api-service.microservices.svc.cluster.local; done"
kubectl run load-generator-3 --image=busybox --restart=Never \
  -n microservices -- /bin/sh -c \
  "while true; do wget -q -O- http://api-service.microservices.svc.cluster.local; done"

# Step 3: Watch scaling (wait 5-10 minutes)
kubectl get hpa -n microservices -w

# Step 4: Stop load
kubectl delete pod load-generator load-generator-2 load-generator-3 -n microservices
```

---

## Checking Platform Health

```bash
# All nodes ready
kubectl get nodes

# All pods running
kubectl get pods --all-namespaces | grep -v Running | grep -v Completed

# HPA status
kubectl get hpa -n microservices

# Alert rules loaded
kubectl get prometheusrule -n monitoring | wc -l
# Expected: 36+

# OpenCost returning data
curl -s "http://localhost:9003/allocation?window=1d" | jq '.code'
# Expected: 200

# Vault status
vault status | grep Sealed
# Expected: Sealed false
```

---

## Troubleshooting

**kubectl connection refused:**
```bash
# Cluster went down — restart
sudo nohup dockerd &
sleep 10
minikube start --profile=prod-sim --force
```

**Pod in CrashLoopBackOff:**
```bash
kubectl logs <pod-name> -n <namespace>
kubectl describe pod <pod-name> -n <namespace>
```

**HPA showing unknown metrics:**
```bash
minikube addons enable metrics-server --profile=prod-sim
sleep 90
kubectl top pods -n microservices
```

**Grafana crashing (memory):**
```bash
free -h  # Check available memory
kubectl scale deployment prometheus-kube-state-metrics \
  -n monitoring --replicas=0
# Free up memory then scale back
```

