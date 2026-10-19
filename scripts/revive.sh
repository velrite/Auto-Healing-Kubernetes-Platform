#!/usr/bin/env bash
cd "$(ls -d /workspaces/*/ | head -1)" || exit 1
ok(){ echo -e "\n\033[1;32m>>> $*\033[0m"; }
warn(){ echo -e "\033[1;33m!!! $*\033[0m"; }
P=prod-sim
vault(){ kubectl exec -i -n vault vault-0 -- env VAULT_TOKEN=root vault "$@"; }
wait_api(){ for i in $(seq 1 60); do kubectl get --raw /readyz >/dev/null 2>&1 && return 0; sleep 5; done; return 1; }
fixnet(){
  sudo modprobe br_netfilter 2>/dev/null
  sudo sysctl -w net.bridge.bridge-nf-call-iptables=0 net.bridge.bridge-nf-call-ip6tables=0 net.ipv4.ip_forward=1 >/dev/null 2>&1
  sudo iptables-legacy -P FORWARD ACCEPT 2>/dev/null; sudo iptables-legacy -I FORWARD 1 -j ACCEPT 2>/dev/null
  sudo iptables -P FORWARD ACCEPT 2>/dev/null; sudo iptables -I FORWARD 1 -j ACCEPT 2>/dev/null
  sudo iptables -I DOCKER-USER 1 -j ACCEPT 2>/dev/null
  for T in iptables iptables-legacy; do
    sudo $T -t nat -C POSTROUTING -s 192.168.49.0/24 ! -d 192.168.49.0/24 -j MASQUERADE 2>/dev/null || \
    sudo $T -t nat -I POSTROUTING 1 -s 192.168.49.0/24 ! -d 192.168.49.0/24 -j MASQUERADE 2>/dev/null
  done
}
ready_nodes(){ kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready"; }
create_cluster(){
  minikube delete --profile=$P >/dev/null 2>&1
  minikube start --profile=$P --nodes=3 --driver=docker --container-runtime=docker \
    --cpus=2 --memory=2500mb --kubernetes-version=v1.31.0 --force
}

ok "1. Machine"
free -m | head -2; df -h / | tail -1
docker image prune -af >/dev/null 2>&1
sudo apt-get clean 2>/dev/null

ok "2. Tools (installs only what is missing)"
command -v jq >/dev/null || { sudo apt-get update -qq; sudo apt-get install -y -qq jq curl >/dev/null; }
kubectl version --client 2>/dev/null | grep -q v1.31 || { sudo curl -sLo /usr/local/bin/kubectl https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl; sudo chmod +x /usr/local/bin/kubectl; }
minikube version 2>/dev/null | grep -q v1.34.0 || { sudo curl -sLo /usr/local/bin/minikube https://storage.googleapis.com/minikube/releases/v1.34.0/minikube-linux-amd64; sudo chmod +x /usr/local/bin/minikube; }
command -v helm >/dev/null || curl -s https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >/dev/null
if [ ! -x /usr/libexec/docker/docker-proxy ]; then
  sudo mkdir -p /usr/libexec/docker
  if [ -x /usr/bin/docker-proxy ]; then sudo cp /usr/bin/docker-proxy /usr/libexec/docker/
  else (cd /tmp && curl -sLO https://download.docker.com/linux/static/stable/x86_64/docker-27.3.1.tgz && tar xzf docker-27.3.1.tgz docker/docker-proxy && sudo cp docker/docker-proxy /usr/libexec/docker/); fi
  sudo chmod +x /usr/libexec/docker/docker-proxy
fi

ok "3. Docker + network fixes"
docker info >/dev/null 2>&1 || { sudo nohup dockerd >/tmp/dockerd.log 2>&1 & sleep 10; }
docker info >/dev/null 2>&1 || { warn "Docker will not start"; tail -20 /tmp/dockerd.log; exit 1; }
fixnet
( while true; do fixnet; sleep 4; done ) & FIXPID=$!
trap 'kill $FIXPID 2>/dev/null' EXIT

ok "4. Cluster (restart if it exists, rebuild if not)"
pkill -f "kubectl port-forward" 2>/dev/null
if docker ps -a --format '{{.Names}}' | grep -qx $P; then
  echo "Existing cluster found, restarting..."
  minikube start --profile=$P --force
else
  echo "No cluster found, building fresh (3-5 min)..."
  create_cluster
fi
kubectl config use-context $P >/dev/null 2>&1
for i in $(seq 1 30); do [ "$(ready_nodes)" -eq 3 ] && break; sleep 10; done
if [ "$(ready_nodes)" -ne 3 ]; then
  warn "Restart did not give 3 Ready nodes. Rebuilding fresh."
  create_cluster; kubectl config use-context $P >/dev/null 2>&1
  for i in $(seq 1 30); do [ "$(ready_nodes)" -eq 3 ] && break; sleep 10; done
fi
[ "$(ready_nodes)" -eq 3 ] || { warn "Still not 3 nodes. Paste this:"; kubectl get nodes; minikube status --profile=$P; exit 1; }
echo -n "Node internet: "; docker exec $P-m02 curl -4 -sI -m 10 https://registry-1.docker.io/v2/ | head -1 | grep -q HTTP && echo OK || { warn "Nodes have no internet"; exit 1; }
minikube addons enable metrics-server --profile=$P >/dev/null 2>&1
wait_api
kubectl get nodes
echo "Letting system pods settle..."; sleep 45

ok "5. Kick any broken pods"
for ns in kube-system microservices monitoring vault opencost; do
  kubectl get pods -n $ns --no-headers 2>/dev/null | grep -E "ImagePull|ErrImage|CrashLoop|Error|Unknown|CreateContainer" | awk '{print $1}' | xargs -r kubectl delete pod -n $ns --wait=false
done

ok "6. Workloads"
for ns in microservices monitoring vault opencost; do kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f - >/dev/null; done
kubectl create secret generic postgres-secret --from-literal=POSTGRES_PASSWORD=apppassword --from-literal=POSTGRES_USER=appuser --from-literal=POSTGRES_DB=appdb -n microservices --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply -f manifests/ >/dev/null; kubectl apply -f database.yaml >/dev/null
kubectl set resources deployment api-service -n microservices --requests=memory=128Mi --limits=memory=256Mi >/dev/null
kubectl get svc postgres-db -n microservices >/dev/null 2>&1 || kubectl expose deployment postgres-db -n microservices --port=5432 --target-port=5432 --name=postgres-db
kubectl rollout status deploy/postgres-db -n microservices --timeout=5m
for d in api-service frontend postgres-db; do kubectl rollout status deploy/$d -n microservices --timeout=3m; done

ok "7. Prometheus + Grafana (installs only if missing)"
if helm status prometheus -n monitoring >/dev/null 2>&1; then echo "already installed"; else
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1; helm repo update >/dev/null
  helm upgrade --install prometheus prometheus-community/kube-prometheus-stack -n monitoring \
    --set grafana.adminPassword=admin --set prometheus.prometheusSpec.retention=2d \
    --set prometheus.prometheusSpec.resources.requests.memory=256Mi --set prometheus.prometheusSpec.resources.limits.memory=800Mi \
    --set grafana.resources.requests.memory=192Mi --set grafana.resources.limits.memory=512Mi \
    --set kubeEtcd.enabled=false --set kubeScheduler.enabled=false --set kubeControllerManager.enabled=false --set kubeProxy.enabled=false \
    --timeout 10m
fi
for i in $(seq 1 40); do
  NOT=$(kubectl get pods -n monitoring --no-headers | grep -vcE "Running|Completed"); echo "[$i] monitoring pods not ready: $NOT"
  [ "$NOT" -eq 0 ] && break; sleep 15
done
kubectl apply -f monitoring/alert-rules.yaml >/dev/null
kubectl label prometheusrule microservices-alerts -n monitoring release=prometheus --overwrite >/dev/null
[ -f monitoring/golden-signals-dashboard.json ] && { kubectl create configmap golden-signals -n monitoring --from-file=monitoring/golden-signals-dashboard.json --dry-run=client -o yaml | kubectl apply -f - >/dev/null; kubectl label configmap golden-signals -n monitoring grafana_dashboard=1 --overwrite >/dev/null; }

ok "8. Vault (reconfigured every time, dev mode forgets on restart)"
if ! helm status vault -n vault >/dev/null 2>&1; then
  helm repo add hashicorp https://helm.releases.hashicorp.com >/dev/null 2>&1
  helm upgrade --install vault hashicorp/vault -n vault --set server.dev.enabled=true --set server.dev.devRootToken=root
  sleep 15
fi
kubectl wait --for=condition=ready pod/vault-0 -n vault --timeout=5m
vault auth list 2>/dev/null | grep -q '^kubernetes/' || vault auth enable kubernetes
vault write auth/kubernetes/config kubernetes_host="https://kubernetes.default.svc" >/dev/null
vault secrets list 2>/dev/null | grep -q '^database/' || vault secrets enable database
vault write database/config/postgres plugin_name=postgresql-database-plugin allowed_roles="api-service-role" \
  connection_url='postgresql://{{username}}:{{password}}@postgres-db.microservices.svc.cluster.local:5432/appdb?sslmode=disable' username="appuser" password="apppassword"
vault write database/roles/api-service-role db_name=postgres creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';" default_ttl="1h" max_ttl="4h" >/dev/null

ok "9. OpenCost + labels"
if ! helm status opencost -n opencost >/dev/null 2>&1; then
  helm repo add opencost https://opencost.github.io/opencost-helm-chart >/dev/null 2>&1
  helm upgrade --install opencost opencost/opencost -n opencost \
    --set opencost.exporter.defaultClusterId=prod-sim --set opencost.prometheus.external.enabled=true \
    --set opencost.prometheus.external.url=http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090 \
    --set opencost.prometheus.internal.enabled=false
fi
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=opencost -n opencost --timeout=5m
kubectl label deployment api-service -n microservices cost-center=platform team=backend environment=production --overwrite >/dev/null
kubectl label deployment frontend -n microservices cost-center=product team=frontend environment=production --overwrite >/dev/null
kubectl label deployment postgres-db -n microservices cost-center=platform team=data environment=production --overwrite >/dev/null

ok "10. Port-forwards + vault shortcut"
grep -q "vault-0 -- env" ~/.bashrc || echo 'vault(){ kubectl exec -i -n vault vault-0 -- env VAULT_TOKEN=root vault "$@"; }' >> ~/.bashrc
cat > ~/pf.sh <<'EOF'
pkill -f "kubectl port-forward" 2>/dev/null
nohup kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n monitoring 9090:9090 >/dev/null 2>&1 &
nohup kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80 >/dev/null 2>&1 &
nohup kubectl port-forward svc/opencost -n opencost 9003:9003 >/dev/null 2>&1 &
sleep 5
EOF
bash ~/pf.sh
sleep 20

ok "FINAL REPORT"
R(){ if eval "$2" >/dev/null 2>&1; then echo -e "\033[1;32mPASS\033[0m  $1"; else echo -e "\033[1;31mFAIL\033[0m  $1"; fi; }
R "3 nodes Ready"                 '[ "$(ready_nodes)" -eq 3 ]'
R "5 microservices pods Running"  '[ "$(kubectl get pods -n microservices --no-headers | grep -c "1/1 *Running")" -ge 5 ]'
R "HPA shows real CPU"            '! kubectl get hpa -n microservices | grep -q unknown'
R "Monitoring pods all Running"   '[ "$(kubectl get pods -n monitoring --no-headers | grep -vcE "Running|Completed")" -eq 0 ]'
R "Vault unsealed"                'vault status | grep -q "Sealed *false"'
R "Vault dynamic creds work"      'vault read database/creds/api-service-role'
R "Vault KV rotation path ready"  'vault kv put secret/api-service/db password=initialpass username=appuser'
R "OpenCost API returns 200"      '[ "$(curl -s "http://localhost:9003/allocation?window=1d" | jq -r .code)" = "200" ]'
R "Prometheus healthy (:9090)"    'curl -sf localhost:9090/-/healthy'
R "Grafana healthy (:3000)"       'curl -sf localhost:3000/api/health'
echo; echo -n "Custom alerts in microservices-alerts: "; kubectl get prometheusrule microservices-alerts -n monitoring -o yaml | grep -c "alert:"
echo -n "Total alerting rules in Prometheus:    "; curl -s localhost:9090/api/v1/rules | jq '[.data.groups[].rules[] | select(.type=="alerting")] | length'
echo; df -h / | tail -1; free -m | head -2
kubectl get pods -A | grep -v -E "Running|Completed"
echo "DONE"
