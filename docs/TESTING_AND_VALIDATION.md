# Testing and Validation

All results from real terminal output. Nothing simulated.
Where first attempts failed or produced unexpected results, that is documented.

---

## Test 1 — Node Failure Recovery

### Setup
```bash
kubectl get pods -n microservices
# All pods Running across prod-sim-m02 and prod-sim-m03
```

[SCREENSHOT: kubectl get pods -n microservices showing all pods Running before test]

### Action
```bash
KILL_TIME=$(date +%s)
minikube node stop prod-sim-m02 --profile=prod-sim
```

### Output
```
✋  Stopping node "prod-sim-m02"  ...
🛑  Powering off "prod-sim-m02" via SSH ...
🛑  Successfully stopped node prod-sim-m02
```

### Recovery measurement
```bash
kubectl wait --for=condition=ready pod -l app=api-service \
  -n microservices --timeout=5m
RECOVERY_TIME=$(date +%s)
ELAPSED=$((RECOVERY_TIME - KILL_TIME))
echo "Recovery: $ELAPSED seconds"
[ $ELAPSED -lt 120 ] && echo "STATUS: SLO MET" || echo "STATUS: INVESTIGATE"
```

### Result
```
pod/api-service-5b795cc4b4-7nt2h condition met
pod/api-service-5b795cc4b4-x9vm5 condition met
Recovery: 20 seconds
STATUS: SLO MET
```

[SCREENSHOT: Terminal showing Recovery: 20 seconds and STATUS: SLO MET]

### What happened
1. prod-sim-m02 stopped
2. Node controller marked it NotReady
3. Scheduler detected pods on NotReady node
4. Pods rescheduled to prod-sim-m03
5. New pods passed readiness checks
6. Total: 20 seconds. Zero manual intervention.

### Restore
```bash
minikube node start prod-sim-m02 --profile=prod-sim
```

---

## Test 2 — Bad Deployment Rollback

### Action
```bash
INCIDENT_START=$(date +%s)
kubectl set image deployment/api-service \
  api-service=kennethreitz/httpbin:this-tag-does-not-exist \
  -n microservices
```

### Pods during incident
```
api-service-5b795cc4b4-x9vm5    1/1   Running          ← old pod, still serving
api-service-785fb7666b-qf2k6    0/1   Pending          ← new pod, bad image
```

### Blast radius
```bash
BAD_PODS=$(kubectl get pods -n microservices | \
  grep -E "ErrImagePull|ImagePullBackOff" | wc -l)
echo "Blast radius: $BAD_PODS pods affected"
# Result: Blast radius: 0 pods affected
```

Why zero: maxUnavailable=0 prevents terminating old pods until
new pods pass readiness. Bad image pods never pass readiness.
Old pods served 100% of traffic throughout.

### Rollback
```bash
kubectl rollout undo deployment/api-service -n microservices
kubectl rollout status deployment/api-service -n microservices --timeout=3m
RECOVERY_TIME=$(date +%s)
echo "Rollback time: $((RECOVERY_TIME - INCIDENT_START)) seconds"
```

### Result
```
deployment "api-service" successfully rolled out
Rollback time: 32 seconds
```

[SCREENSHOT: Terminal showing Rollback time: 32 seconds and deployment successfully rolled out]

---

## Test 3 — HPA Traffic Spike

### Note on first attempt
First HPA check showed `cpu: <unknown>/60%` because metrics-server
addon was not enabled. Fixed:
```bash
minikube addons enable metrics-server --profile=prod-sim
```
Second attempt produced real CPU measurements.

### Before load
```
=== BEFORE LOAD ===
Sun Jul  5 17:21:25 UTC 2026
api-service-hpa   cpu: 4%/60%, memory: 84%/70%   REPLICAS: 2
Pods: 2
```

[SCREENSHOT: BEFORE LOAD showing 2 pods and cpu: 4%/60%]

### Load generators
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
```

### During load (7 minutes after start)
```
=== DURING LOAD ===
Sun Jul  5 17:28:24 UTC 2026
api-service-hpa   cpu: 86%/60%, memory: 75%/70%   REPLICAS: 8
Pods: 8
```

[SCREENSHOT: DURING LOAD showing 8 pods and cpu: 86%/60%]

### After scale down
```
=== SCALE DOWN ===
Sun Jul  5 17:47:33 UTC 2026
api-service-hpa   cpu: 2%/60%, memory: 61%/70%   REPLICAS: 2
Pods: 2
```

[SCREENSHOT: SCALE DOWN showing 2 pods and cpu: 2%/60%]

### Summary
- Before: 2 pods, CPU 4%
- Peak: 8 pods, CPU 86%
- Scale up time: ~7 minutes
- Scale down: automatic after load removed
- Human intervention: zero

---

## Test 4 — Vault Secret Rotation

### Setup
```bash
kubectl port-forward svc/vault -n vault 8200:8200 &
export VAULT_ADDR='http://127.0.0.1:8200'
vault login root
vault secrets enable kv-v2
```

### Dynamic credentials — database secrets engine
```bash
vault read database/creds/api-service-role
# First call:
# username: v-token-api-serv-gEPO9LhamjlaTeH0t64B
# password: IPajNfeka-8FPxnlA6mm

vault read database/creds/api-service-role
# Second call:
# username: v-token-api-serv-BFBNaV6l2QZ46MiXywmX
# password: pQC2dk-z9dNxl3xwAd3G
```

Two completely different credentials. That is dynamic secrets.

### KV v2 rotation test
```bash
vault kv put secret/api-service/db \
  password="initialpassword123" username="appuser"
# version 1 written

vault kv put secret/api-service/db \
  password="rotatedpassword456" username="appuser"
# version 2 written — rotation complete
```

### App status during rotation
```bash
kubectl get pods -n microservices
# All pods Running — zero restarts
```

[SCREENSHOT: Full rotation output and kubectl get pods showing all Running]

### Zero credential exposure proof
```bash
kubectl describe pod -l app=api-service -n microservices | grep -i password
# Returns nothing
```

[SCREENSHOT: grep returning nothing — zero credentials visible]
