# Incidents

Real problems encountered. What happened, root cause, fix, prevention.

---

## Incident 1 — Docker Proxy Binary Missing

### What happened
```
error forwarding port: fork/exec
/usr/libexec/docker/docker-proxy: no such file or directory
```
Minikube would not start.

### Root cause
GitHub Codespaces ships moby-engine, not docker-ce.
moby-engine does not include docker-proxy.
Minikube requires it to map container ports for the API server.
Not documented in Minikube troubleshooting guide.

### Fix
```bash
cd /tmp
apt download docker-ce
dpkg -x docker-ce_*.deb docker-extract
sudo mkdir -p /usr/libexec/docker
sudo cp docker-extract/usr/bin/docker-proxy /usr/libexec/docker/
sudo chmod +x /usr/libexec/docker/docker-proxy
```

### Prevention
Added as first step in runbook. Must run before minikube start
on any new Codespace.

---

## Incident 2 — Memory Exhaustion Under Full Stack

### What happened
Grafana crashed repeatedly with CrashLoopBackOff.
Free memory: 131MB.
kubectl commands started returning connection refused.
Helm install timed out.

### Root cause
8GB RAM with 3-node cluster, Prometheus, Grafana, Vault, and
Kubecost (which bundles its own Prometheus) simultaneously
exceeded available memory.

### Fix
Switched from Kubecost to OpenCost — no bundled Prometheus.
Scaled down non-critical components before installing new tools:
```bash
kubectl scale deployment prometheus-grafana -n monitoring --replicas=0
kubectl scale deployment prometheus-kube-state-metrics -n monitoring --replicas=0
```

### Prevention
Run `free -h` before any new Helm install.
Prefer tools that integrate with existing Prometheus over those
that bundle their own.

---

## Incident 3 — Git History Contaminated with Large Binaries

### What happened
```
remote: error: File minikube-linux-amd64 is 128.64 MB;
this exceeds GitHub file size limit of 100.00 MB
```
Push rejected. Happened three separate times with different binaries.

### Root cause
`git add .` picked up kubectl (53.7MB), minikube (128.64MB), and
vault zip (128.06MB) sitting in the project directory.

### Fix
```bash
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch kubectl minikube-linux-amd64 \
   vault_1.15.0_linux_amd64.zip nohup.out" \
  --prune-empty --tag-name-filter cat -- --all
git push origin main --force
```

### Prevention
.gitignore is now the first file created on every project.
Tools downloaded to /tmp or /usr/local/bin, not project directory.

---

## Incident 4 — Kubecost Permission Denied

### What happened
```
ERR AllocationReportFileStore: error creating file store:
open /var/configs/reports.json: permission denied
mkdir /var/configs/db: permission denied
panic: runtime error: invalid memory address or nil pointer dereference
```

### Root cause
Kubecost requires write access to /var/configs.
Codespace container security context restricts this.
Three install attempts all failed.

### Fix
Switched to OpenCost — open source upstream Kubecost is built on.
No storage permission requirements. Confirmed working with real data.

### Prevention
For Minikube and Codespace environments use OpenCost.
Kubecost needs privileged containers or custom security context.

---

## Incident 5 — HPA Showing Unknown Metrics

### What happened
```
api-service-hpa   cpu: <unknown>/60%   REPLICAS: 2
```
Load generators ran. Pod count never changed.

### Root cause
metrics-server addon not enabled. HPA had no CPU data to act on.

### Fix
```bash
minikube addons enable metrics-server --profile=prod-sim
# Wait 90 seconds
kubectl top pods -n microservices
```

### Prevention
Enable metrics-server during cluster setup before any HPA testing.
