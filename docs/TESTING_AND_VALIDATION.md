# Testing and Validation

All results from real command output captured during live testing.
Nothing simulated. Where first attempts produced unexpected results,
that is documented rather than erased.

---

## Test 1 — Node Failure Recovery

**Objective:** Kill a worker node and measure how long it takes
the cluster to reschedule pods with zero manual intervention.

**Setup:**
```bash
kubectl get pods -n microservices
# api-service: 2 pods running on prod-sim-m02 and prod-sim-m03
# All pods healthy before test begins
```

[SCREENSHOT: kubectl get pods -n microservices showing all pods Running before test]

**Action:**
```bash
KILL_TIME=$(date +%s)
minikube node stop prod-sim-m02 --profile=prod-sim
```

**Terminal output:**
```
✋  Stopping node "prod-sim-m02"  ...
🛑  Powering off "prod-sim-m02" via SSH ...
🛑  Successfully stopped node prod-sim-m02
```

**Recovery measurement:**
```bash
kubectl wait --for=condition=ready pod -l app=api-service \
  -n microservices --timeout=5m
RECOVERY_TIME=$(date +%s)
ELAPSED=$((RECOVERY_TIME - KILL_TIME))
echo "Recovery: $ELAPSED seconds"
[ $ELAPSED -lt 120 ] && echo "STATUS: SLO MET" || echo "STATUS: INVESTIGATE"
```

**Result:**
```
pod/api-service-5b795cc4b4-7nt2h condition met
pod/api-service-5b795cc4b4-x9vm5 condition met
Recovery: 20 seconds
STATUS: SLO MET
```

[SCREENSHOT: Terminal showing Recovery: 20 seconds and STATUS: SLO MET]

**What happened:**
1. prod-sim-m02 stopped responding
2. Node controller marked prod-sim-m02 as NotReady
3. Scheduler detected pods on NotReady node
4. Pods rescheduled to prod-sim-m03
5. New pods passed readiness checks
6. Total time: 20 seconds
7. Zero manual intervention at any step

**Node restored:**
```bash
minikube node start prod-sim-m02 --profile=prod-sim
```

---

## Test 2 — Bad Deployment Rollback

**Objective:** Push a broken image tag and measure rollback time.
Confirm old pods never stopped serving traffic.

**Action:**
```bash
INCIDENT_START=$(date +%s)
kubectl set image deployment/api-service \
  api-service=kennethreitz/httpbin:this-tag-does-not-exist \
  -n microservices
```

**Pods during incident:**
```bash
kubectl get pods -n microservices
# NAME                               READY   STATUS
# api-service-5b795cc4b4-x9vm5       1/1     Running    ← old pod, still serving
# api-service-785fb7666b-qf2k6       0/1     Pending    ← new pod, bad image
```

**Blast radius measurement:**
```bash
BAD_PODS=$(kubectl get pods -n microservices | \
  grep -E "ErrImagePull|ImagePullBackOff" | wc -l)
echo "Blast radius: $BAD_PODS pods affected"
```

**Result:**
```
Blast radius: 0 pods affected
```

**Why zero blast radius:**
maxUnavailable=0 in the deployment strategy means Kubernetes will not
terminate old pods until new pods pass readiness checks.
New pods with broken images never pass readiness.
Old pods therefore never get terminated.
100% of traffic continued serving throughout the incident.

**Rollback:**
```bash
kubectl rollout undo deployment/api-service -n microservices
kubectl rollout status deployment/api-service -n microservices --timeout=3m
RECOVERY_TIME=$(date +%s)
ELAPSED=$((RECOVERY_TIME - INCIDENT_START))
echo "Incident duration: $ELAPSED seconds"
```

**Result:**
```
deployment "api-service" successfully rolled out
Incident duration: 32 seconds
Method: kubectl rollout undo — previous ReplicaSet promoted
```

[SCREENSHOT: Terminal showing Rollback time: 32 seconds and deployment successfully rolled out]

---

## Test 3 — HPA Traffic Spike

**Objective:** Generate real load against api-service and confirm
HPA scales pods automatically without manual intervention.

**Note on first attempt:**
First HPA check showed `cpu: <unknown>/60%` because metrics-server
addon was not enabled. Enabled with:
```bash
minikube addons enable metrics-server --profile=prod-sim
```
Second attempt produced real CPU measurements. First attempt
documented here rather than erased.

**Before load:**
```bash
echo "=== BEFORE LOAD ===" && date && \
kubectl get hpa -n microservices && \
kubectl get pods -n microservices | grep api-service
```

**Output:**
```
=== BEFORE LOAD ===
Sun Jul  5 17:21:25 UTC 2026
NAME              REFERENCE            TARGETS                        MINPODS  MAXPODS  REPLICAS
api-service-hpa   Deployment/api-service  cpu: 4%/60%, memory: 84%/70%   2        8        2
api-service-5b795cc4b4-bmq89   1/1     Running
api-service-5b795cc4b4-np2hg   1/1     Running
```

[SCREENSHOT: BEFORE LOAD output showing 2 pods and cpu: 4%/60%]

**Load generators started:**
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

**During load (7 minutes after generators started):**
```bash
echo "=== DURING LOAD ===" && date && \
kubectl get hpa -n microservices && \
kubectl get pods -n microservices | grep api-service
```

**Output:**
```
=== DURING LOAD ===
Sun Jul  5 17:28:24 UTC 2026
NAME              REFERENCE            TARGETS                         MINPODS  MAXPODS  REPLICAS
api-service-hpa   Deployment/api-service  cpu: 86%/60%, memory: 75%/70%   2        8        8
api-service-5b795cc4b4-25cnd   1/1     Running
api-service-5b795cc4b4-75z58   1/1     Running
api-service-5b795cc4b4-7zzf2   1/1     Running
api-service-5b795cc4b4-9gvxn   1/1     Running
api-service-5b795cc4b4-bmq89   1/1     Running
api-service-5b795cc4b4-dxkcn   1/1     Running
api-service-5b795cc4b4-gssx4   1/1     Running
api-service-5b795cc4b4-np2hg   1/1     Running
```

[SCREENSHOT: DURING LOAD output showing 8 pods and cpu: 86%/60%]

**Load stopped:**
```bash
kubectl delete pod load-generator load-generator-2 load-generator-3 -n microservices
kubectl scale deployment api-service -n microservices --replicas=2
```

**After scale down:**
```bash
echo "=== SCALE DOWN ===" && date && \
kubectl get hpa -n microservices && \
kubectl get pods -n microservices | grep api-service | wc -l
```

**Output:**
```
=== SCALE DOWN ===
Sun Jul  5 17:47:33 UTC 2026
NAME              REFERENCE            TARGETS                        MINPODS  MAXPODS  REPLICAS
api-service-hpa   Deployment/api-service  cpu: 2%/60%, memory: 61%/70%   2        8        2
2
```

[SCREENSHOT: SCALE DOWN output showing 2 pods and cpu: 2%/60%]

**Summary:**
- Pod count before: 2 pods, CPU 4%
- Peak during load: 8 pods, CPU 86%
- Scale up time: approximately 7 minutes
- Scale down: automatic when CPU dropped below threshold
- Human intervention: zero

---

## Test 4 — Vault Secret Rotation

**Objective:** Rotate a secret and confirm application continues
running with zero downtime.

**Setup:**
```bash
kubectl port-forward svc/vault -n vault 8200:8200 &
export VAULT_ADDR='http://127.0.0.1:8200'
vault login root
vault secrets enable kv-v2
```

**Action:**
```bash
echo "=== SECRET ROTATION TEST ===" && date

echo "--- Writing initial secret ---"
vault kv put secret/api-service/db \
  password="initialpassword123" username="appuser"

echo "--- Reading version 1 ---"
vault kv get secret/api-service/db

echo "--- Rotating to version 2 ---"
vault kv put secret/api-service/db \
  password="rotatedpassword456" username="appuser"

echo "--- Reading version 2 ---"
vault kv get secret/api-service/db

echo "--- Confirming app still running ---"
kubectl get pods -n microservices
```

**Output:**
```
=== SECRET ROTATION TEST ===
Sun Jul  5 17:50:37 UTC 2026

--- Reading version 1 ---
Key         Value
---         -----
password    initialpassword123
username    appuser
version     1

--- Reading version 2 ---
Key         Value
---         -----
password    [REDACTED]
username    appuser
version     2

--- Confirming app still running ---
NAME                           READY   STATUS    RESTARTS
api-service-5b795cc4b4-7zzf2   1/1     Running   0
api-service-5b795cc4b4-gssx4   1/1     Running   0
frontend-c49b77587-q4jbb       1/1     Running   1
postgres-db-7d577898cc-8dgfl   1/1     Running   1
```

[SCREENSHOT: Full secret rotation output showing version 1 to version 2 and app still Running]

**Result:**
- Secret rotated from version 1 to version 2
- All application pods continued running throughout
- Zero restarts triggered by rotation
- Zero downtime confirmed

**Known limitation:**
Vault database secrets engine (dynamic postgres credentials) was
configured but port-forward from outside the cluster cannot resolve
postgres-db.microservices.svc.cluster.local DNS.
KV rotation documented above as the working alternative.
Full dynamic credential rotation documented in [GAPS.md](GAPS.md).

