# Runbook

## Starting After Codespace Restart

Step 1 — Fix docker-proxy if missing:
```bash
ls /usr/libexec/docker/docker-proxy || (
  cd /tmp
  apt download docker-ce -y
  dpkg -x docker-ce_*.deb docker-extract
  sudo mkdir -p /usr/libexec/docker
  sudo cp docker-extract/usr/bin/docker-proxy /usr/libexec/docker/
  sudo chmod +x /usr/libexec/docker/docker-proxy
)
```

Step 2 — Start Docker:
```bash
sudo nohup dockerd &
sleep 10
docker ps
```

Step 3 — Start Minikube:
```bash
minikube start --profile=prod-sim --force
```

Step 4 — Verify:
```bash
kubectl get nodes
kubectl get pods --all-namespaces | grep -v Completed
```

Step 5 — Restore port-forwards:
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

## Service Access

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | http://localhost:3000 | admin / from vault secret |
| Prometheus | http://localhost:9090 | none |
| OpenCost | http://localhost:9003 | none |
| Vault UI | http://localhost:8200 | token: root |

---

## Node Failure Test
```bash
KILL_TIME=$(date +%s)
minikube node stop prod-sim-m02 --profile=prod-sim
kubectl wait --for=condition=ready pod -l app=api-service \
  -n microservices --timeout=5m
RECOVERY_TIME=$(date +%s)
echo "Recovery: $((RECOVERY_TIME - KILL_TIME)) seconds"
minikube node start prod-sim-m02 --profile=prod-sim
```

## Bad Deployment Test
```bash
INCIDENT_START=$(date +%s)
kubectl set image deployment/api-service \
  api-service=kennethreitz/httpbin:this-tag-does-not-exist \
  -n microservices
sleep 30
kubectl rollout undo deployment/api-service -n microservices
RECOVERY_TIME=$(date +%s)
echo "Rollback: $((RECOVERY_TIME - INCIDENT_START)) seconds"
```

## HPA Load Test
```bash
kubectl run load-generator --image=busybox --restart=Never \
  -n microservices -- /bin/sh -c \
  "while true; do wget -q -O- http://api-service.microservices.svc.cluster.local; done"
kubectl run load-generator-2 --image=busybox --restart=Never \
  -n microservices -- /bin/sh -c \
  "while true; do wget -q -O- http://api-service.microservices.svc.cluster.local; done"
kubectl run load-generator-3 --image=busybox --restart=Never \
  -n microservices -- /bin/sh -c \
  "while true; do wget -q -O- http://api-service.microservices.svc.cluster.local; done"
# Watch HPA
kubectl get hpa -n microservices -w
# Stop load
kubectl delete pod load-generator load-generator-2 load-generator-3 -n microservices
```

---

## Troubleshooting

kubectl connection refused:
```bash
sudo nohup dockerd &
sleep 10
minikube start --profile=prod-sim --force
```

HPA showing unknown:
```bash
minikube addons enable metrics-server --profile=prod-sim
sleep 90
kubectl top pods -n microservices
```

Pod in CrashLoopBackOff:
```bash
kubectl logs <pod-name> -n <namespace>
kubectl describe pod <pod-name> -n <namespace>
```

Memory pressure:
```bash
free -h
kubectl scale deployment prometheus-grafana -n monitoring --replicas=0
```
