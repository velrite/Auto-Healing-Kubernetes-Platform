# Architecture Decision Records

---

## ADR-001 — Minikube over kind

Context: needed a local multi-node Kubernetes cluster.

Decision: Minikube with Docker driver, 3 nodes.

Alternatives rejected:
- kind — lighter and faster. Same docker-proxy issue would occur.
  Minikube has better addon support (metrics-server, ingress, dashboard)
  reducing manual setup.
- k3s — single-node by default. Multi-node needs k3sup. More overhead.

Trade-off: Minikube is heavier. 3-5 minute startup vs 30 seconds for kind.
Acceptable because addon ecosystem reduces configuration significantly.

---

## ADR-002 — OpenCost over Kubecost

Context: needed cost visibility per namespace and service.

Decision: OpenCost.

Alternatives rejected:
- Kubecost — three installation attempts all failed with permission denied
  on /var/configs. Also deploys bundled Prometheus which conflicted with
  existing Prometheus and exhausted memory.

Trade-off: OpenCost has simpler UI. Cost API returns raw JSON rather
than formatted dashboard views. Sufficient for proving cost visibility.

---

## ADR-003 — GitHub Actions over GitLab CI

Context: needed a CI/CD pipeline.

Decision: GitHub Actions.

Alternatives rejected:
- GitLab CI — requires separate account, separate project, connecting
  external cluster. Additional overhead with no technical advantage.

Trade-off: GitHub Actions free tier is 2000 minutes/month on public repos.
Pipeline runs in ~48 seconds. No additional account required.

---

## ADR-004 — Vault Dev Mode over Standalone

Context: needed secrets management without static credentials.

Decision: Vault dev mode, root token.

Alternatives rejected:
- Standalone with file storage — requires manual init and unseal on every
  Minikube restart. State is lost on restart anyway on non-persistent
  Codespace volume. Dev mode and standalone behave identically in practice.

Trade-off: dev mode is not for production. Root token is not a production
pattern. Acceptable for demonstrating dynamic secrets concepts.

---

## ADR-005 — Canary via CI over Argo Rollouts

Context: needed progressive delivery with automatic rollback.

Decision: canary logic in GitHub Actions pipeline.

Alternatives rejected:
- Argo Rollouts — implemented in Project 3. For this project, CI-based
  canary demonstrates the underlying mechanism without additional CRD complexity.

Trade-off: CI canary has no traffic splitting by percentage. Rollback is
restart-count based rather than error-rate based. Acceptable for this stage.
