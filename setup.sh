# Install kind
if ! command -v kind > /dev/null
then
  # For AMD64 / x86_64
  [ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
  # For ARM64
  [ $(uname -m) = aarch64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-arm64
  chmod +x ./kind
  sudo mv ./kind /usr/local/bin/kind
else
  echo "kind is already installed"
fi

# Create cluster
[ ! "$(kind get clusters)" = kind ] && kind create cluster --config=kind-config.yaml

# Install clis

# Cilium
if ! command -v cilium > /dev/null
then
  CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
  CLI_ARCH=amd64
  if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
  curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
  sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
  sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
  rm cilium-linux-${CLI_ARCH}.tar.gz
  rm cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
else
  echo cilium cli is installed
fi

# Hubble
if ! command -v hubble > /dev/null
then
  HUBBLE_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)
  HUBBLE_ARCH=amd64
  if [ "$(uname -m)" = "aarch64" ]; then HUBBLE_ARCH=arm64; fi
  curl -L --fail --remote-name-all https://github.com/cilium/hubble/releases/download/$HUBBLE_VERSION/hubble-linux-${HUBBLE_ARCH}.tar.gz{,.sha256sum}
  sha256sum --check hubble-linux-${HUBBLE_ARCH}.tar.gz.sha256sum
  sudo tar xzvfC hubble-linux-${HUBBLE_ARCH}.tar.gz /usr/local/bin
  rm hubble-linux-${HUBBLE_ARCH}.tar.gz
  rm hubble-linux-${HUBBLE_ARCH}.tar.gz.sha256sum
else
  echo hubble cli is installed
fi

# Install cilium and hubble
[ $(kubectl get daemonset -n kube-system cilium --no-headers | wc -l) = 0 ] && cilium install --version 1.14.6
[ $(kubectl get deploy -n kube-system hubble-relay --no-headers | wc -l) = 0 ] && cilium hubble enable --ui
cilium status --wait

# Install ingress
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
export __HOST__=$(kubectl get nodes kind-control-plane -o jsonpath="{.status.addresses[0].address}")
export __PORT__=$(kubectl get svc -n ingress-nginx ingress-nginx-controller --no-headers -o jsonpath="{.spec.ports[0].nodePort}")

# Deploy star wars demo
kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/1.14.6/examples/minikube/http-sw-app.yaml
kubectl apply -f demo/ingress.yaml

# Run proxy
envsubst '$__HOST__,$__PORT__' < proxy/nginx.conf.template > proxy/nginx.conf
docker compose -f proxy/docker-compose.yml up -d
