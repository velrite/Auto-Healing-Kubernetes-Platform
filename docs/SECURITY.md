# Security

## Secrets Management

### What Was Done
HashiCorp Vault deployed in vault namespace.
No static credentials stored in any YAML file committed to Git.

**postgres-secret:** Created via kubectl command, not stored in any file:
```bash
kubectl create secret generic postgres-secret \
  --from-literal=POSTGRES_PASSWORD=apppassword \
  --from-literal=POSTGRES_USER=appuser \
  --from-literal=POSTGRES_DB=appdb \
  -n microservices
```

**Proof of zero exposed credentials:**
```bash
kubectl describe pod -l app=api-service -n microservices | grep -i password
# Returns nothing — zero credentials visible
```

[SCREENSHOT: kubectl describe pod output showing no password fields]

### Vault KV v2
Secret versioning enabled. Rotation tested and validated.
Previous version retained — rollback to previous secret without redeployment.

---

## Git Security

### .gitignore
```
*.tfstate
*.tfstate.backup
*.tfvars
.terraform/
vault-init.json
*.zip
nohup.out
kubectl
minikube-linux-amd64
vault_1.15.0_linux_amd64.zip
```

### Incident — Binaries Committed to Git
Large binaries were accidentally committed during the build.
Git history was rewritten three times using filter-branch.
See [INCIDENTS.md](INCIDENTS.md#incident-3--git-history-contaminated-with-large-binaries).

---

## Network Security

- Pods communicate within cluster using cluster-internal DNS
- No external exposure except frontend NodePort on port 30421
- api-service exposed only as ClusterIP — not reachable externally
- postgres-db exposed only as ClusterIP — database not externally accessible

---

## What Is Not Secured (Documented Gaps)

- No NetworkPolicies applied — all pods can reach all other pods within cluster
- No Pod Security Standards enforced — pods can run as root
- No image signing or verification
- No admission controller restricting image sources

See [GAPS.md](GAPS.md) for what building these properly would require.

