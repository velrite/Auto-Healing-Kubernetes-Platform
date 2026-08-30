# Incidents

Real problems encountered during this build.
Every entry follows: What Happened → Root Cause → Fix → Prevention.
Nothing hypothetical.

---

## Incident 1 — Docker Proxy Binary Missing

**What happened:**
Minikube failed to start with:
```
error forwarding port: fork/exec /usr/libexec/docker/docker-proxy: no such file or directory
```

Spent significant time attempting various Docker reinstallation approaches
before identifying the actual root cause.

**Root cause:**
GitHub Codespaces ships with moby-engine — Microsoft's Docker fork.
moby-engine does not include docker-proxy.
Minikube expects docker-proxy at /usr/libexec/docker/docker-proxy to map
container ports for the Kubernetes API server.
This is not documented anywhere in Minikube's official troubleshooting guide.

**Fix:**
```bash
cd /tmp
apt download docker-ce
dpkg -x docker-ce_*.deb docker-extract
sudo mkdir -p /usr/libexec/docker
sudo cp docker-extract/usr/bin/docker-proxy /usr/libexec/docker/
sudo chmod +x /usr/libexec/docker/docker-proxy
minikube start --profile=prod-sim --force
```

**Prevention:**
Added to runbook as first step on any new Codespace.
Must be done before minikube start.

---

## Incident 2 — Memory Exhaustion Under Full Stack

**What happened:**
Grafana kept crashing with CrashLoopBackOff during Kubecost installation.
Free memory reported:
```
Mem: 7.8Gi total, 5.4Gi used, 195Mi free
```

Helm install timed out. Cluster API server became unresponsive.
kubectl commands started returning connection refused.

**Root cause:**
8GB Codespace RAM is insufficient when running simultaneously:
- 3-node Minikube cluster
- Prometheus + Grafana + Alertmanager
- HashiCorp Vault
- Kubecost (additional Prometheus instance)

Kubecost deploys its own bundled Prometheus which conflicted with
the existing Prometheus installation and exhausted available memory.

**Fix:**
1. Switched from Kubecost to OpenCost (lighter, no bundled Prometheus)
2. Scaled down non-critical components before installing new tools:
```bash
kubectl scale deployment prometheus-grafana -n monitoring --replicas=0
kubectl scale deployment prometheus-kube-state-metrics -n monitoring --replicas=0
```
3. Installed new component
4. Scaled everything back up

**Prevention:**
Run `free -h` before any new Helm install.
Available memory should be above 2GB before proceeding.
Prefer tools that integrate with existing Prometheus over tools
that bundle their own.

---

## Incident 3 — Git History Contaminated with Large Binaries

**What happened:**
git push rejected by GitHub three separate times:
```
remote: error: File minikube-linux-amd64 is 128.64 MB;
this exceeds GitHub file size limit of 100.00 MB
remote: error: File kubectl is 56.75 MB;
this is larger than GitHub recommended maximum of 50.00 MB
```

**Root cause:**
`git add .` picked up binary files sitting in the project directory:
- kubectl (53.7 MB)
- minikube-linux-amd64 (128.64 MB)
- vault_1.15.0_linux_amd64.zip (128.06 MB)

These were downloaded to the project directory during tool installation
and not excluded from git tracking before the first commit.

**Fix — required three separate rewrites:**
```bash
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch kubectl kubectl.sha256 \
   minikube-linux-amd64 nohup.out vault_1.15.0_linux_amd64.zip" \
  --prune-empty --tag-name-filter cat -- --all
git push origin main --force
```

Also used git-filter-repo to scrub a hardcoded password from history:
```bash
git filter-repo --replace-text <(echo "admin123secure==>REDACTED") --force
git push origin main --force
```

**Prevention:**
.gitignore is now the first file created on every new project.
Never run `git add .` without first checking `git status` output.
Download tools to /tmp or /usr/local/bin, not the project directory.

---

## Incident 4 — Kubecost Permission Denied

**What happened:**
Kubecost cost-analyzer pod crashed repeatedly with:
```
ERR AllocationReportFileStore: error creating file store:
open /var/configs/reports.json: permission denied
ERR Store[1h]: NewETLStore: error creating storage:
mkdir /var/configs/db: permission denied
panic: runtime error: invalid memory address or nil pointer dereference
```

**Root cause:**
Kubecost requires write access to /var/configs which is restricted
by the Codespace container security context. The container cannot
write to this path without elevated privileges.

**Fix:**
Switched to OpenCost — the open source upstream that Kubecost is based on.
OpenCost does not have the same storage permission requirements.
OpenCost confirmed working — real cost data returned via API.

**Prevention:**
For Minikube/Codespace environments, prefer OpenCost over Kubecost.
Kubecost requires either privileged containers or a custom security
context that may not be available in restricted environments.

---

## Incident 5 — HPA Showing Unknown Metrics

**What happened:**
First HPA load test showed:
```
NAME              TARGETS                REPLICAS
api-service-hpa   cpu: <unknown>/60%     2
```
CPU was unknown so HPA could not scale. Load generators ran but
pod count never changed.

**Root cause:**
metrics-server addon was not enabled in Minikube.
Without metrics-server, HPA has no CPU data to act on.

**Fix:**
```bash
minikube addons enable metrics-server --profile=prod-sim
# Wait 90 seconds
kubectl top pods -n microservices
# Confirmed real CPU numbers
```

Second test run produced correct CPU percentages and HPA scaled
from 2 to 8 pods at 86% CPU utilization.

**Prevention:**
Enable metrics-server as part of cluster setup, before any HPA testing.
Add to runbook under prerequisites.

