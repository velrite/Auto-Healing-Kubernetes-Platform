# Architecture Decision Records

Every significant decision with context, alternatives rejected,
trade-off accepted, and what would change the decision.

---

## ADR-001 — Minikube over kind

**Context:**
Needed a local multi-node Kubernetes cluster for development and testing.

**Decision:** Minikube with Docker driver, 3 nodes.

**Alternatives rejected:**
- **kind** — lighter and faster startup. Would have had the same docker-proxy
  issue in Codespaces. Better addon support in Minikube made it preferable
  for this project (metrics-server, ingress-nginx, dashboard all available
  as built-in addons).
- **k3s** — excellent for single-node. Multi-node setup requires k3sup or
  manual configuration. More operational overhead than Minikube for this use case.

**Trade-off accepted:**
Minikube is heavier than kind. Startup takes 3-5 minutes vs 30 seconds for kind.
8GB RAM gets tight running full stack. Acceptable because addon ecosystem
reduces manual setup significantly.

**What would revisit this:**
A machine with 16GB+ RAM. kind would be preferable for faster iteration.

---

## ADR-002 — OpenCost over Kubecost

**Context:**
Needed real-time cost visibility per namespace and service.

**Decision:** OpenCost.

**Alternatives rejected:**
- **Kubecost** — three installation attempts all failed with permission denied
  on /var/configs in the Codespace security context. Also deploys its own
  bundled Prometheus which conflicted with the existing Prometheus installation
  and exhausted available memory.

**Trade-off accepted:**
OpenCost has less UI polish than Kubecost. The web dashboard is simpler.
For this project the cost API returning real JSON data was sufficient proof.
The underlying cost model is identical — OpenCost is the upstream that
Kubecost is built on.

**What would revisit this:**
Kubecost on a real cloud cluster with full node permissions and dedicated
monitoring infrastructure.

---

## ADR-003 — GitHub Actions over GitLab CI

**Context:**
Needed a CI/CD pipeline for deployment automation and validation.

**Decision:** GitHub Actions.

**Alternatives rejected:**
- **GitLab CI** — requires creating a separate GitLab account, setting up
  a new project, and connecting the external cluster. Additional account
  management overhead with no technical advantage for this use case.

**Trade-off accepted:**
GitHub Actions free tier (2000 minutes/month on public repos) is sufficient.
Pipeline runs in approximately 48 seconds. No additional account required.

---

## ADR-004 — Vault Dev Mode over Standalone Mode

**Context:**
Needed secrets management to eliminate static credentials.

**Decision:** Vault dev mode with root token.

**Alternatives rejected:**
- **Vault standalone mode with file storage** — requires manual init and unseal
  on every Minikube restart. Would add 3 manual commands to every session startup.
  State is lost on restart regardless — file storage on a non-persistent
  Codespace volume behaves the same as dev mode in practice.

**Trade-off accepted:**
Dev mode is explicitly not for production. Root token is not a production pattern.
Acceptable for demonstrating dynamic secrets concepts in a demo environment where
the cluster is rebuilt regularly anyway.

**What would revisit this:**
Vault on a persistent cluster with Vault Agent Injector for automatic
secret injection into pod filesystems without application code changes.

---

## ADR-005 — Canary via CI over Argo Rollouts

**Context:**
Needed progressive delivery with automatic rollback.

**Decision:** Canary logic implemented in GitHub Actions pipeline.

**Alternatives rejected:**
- **Argo Rollouts** — installed in Project 3 (GitOps platform). For this project,
  implementing canary in the CI pipeline demonstrates understanding of the
  underlying mechanism without the additional complexity of Argo Rollouts CRDs.

**Trade-off accepted:**
CI-based canary is less sophisticated than Argo Rollouts.
No traffic splitting by percentage. No SLO-based promotion.
Rollback is based on restart count rather than error rate.
Acceptable for demonstrating the canary concept at this stage.

