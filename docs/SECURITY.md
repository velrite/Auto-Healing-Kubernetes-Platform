# Security

## No Static Credentials

No passwords stored in any YAML file committed to Git.

postgres-secret created via kubectl — not stored in any file:
```bash
kubectl create secret generic postgres-secret \
  --from-literal=POSTGRES_PASSWORD=apppassword \
  --from-literal=POSTGRES_USER=appuser \
  --from-literal=POSTGRES_DB=appdb \
  -n microservices
```

Proof:
```bash
kubectl describe pod -l app=api-service -n microservices | grep -i password
# Returns nothing
```

---

## Vault Dynamic Secrets

### Database secrets engine
- api-service-role configured with 1h TTL
- Every credential request generates a unique username and password
- Credentials expire automatically after 1 hour
- Revoking a lease immediately invalidates the credential

### KV v2
- Version history maintained
- Rotation does not require pod restart
- Previous version available for rollback

### Vault initialization
- 5 key shares generated, threshold of 3 required to unseal
- vault-init.json immediately added to .gitignore after generation
- Never committed to Git

---

## Git Security

.gitignore excludes:
- vault-init.json
- *.tfstate and *.tfstate.backup
- *.tfvars
- Large binaries — kubectl, minikube, vault zip

Git history was rewritten 3 times using filter-branch to remove
accidentally committed binaries. See [INCIDENTS.md](INCIDENTS.md).

---

## What Is Not Secured

- No NetworkPolicies — all pods can reach each other within cluster
- No Pod Security Standards enforcement
- No image signing
- No admission controller beyond default Kubernetes

These are documented gaps — not silent omissions.
See [GAPS.md](GAPS.md) for what building them would require.
