# Cilium Star Wars Demo

## Setup

### Install kind

```sh
# For AMD64 / x86_64
[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
# For ARM64
[ $(uname -m) = aarch64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-arm64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

### Setup cluster

```yaml
# kind-config.yaml

kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
  - role: worker
  - role: worker
networking:
  disableDefaultCNI: true
```

```sh
kind create cluster --config=kind-config.yaml
```

### Install cilium

First cli

```sh
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
```

Then pods

```sh
cilium install --version 1.14.6
```

Then check status

```sh
cilium status --wait
```

### Install hubble

First enable with ui

```sh
cilium hubble enable --ui
```

Then cli

```sh
HUBBLE_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)
HUBBLE_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then HUBBLE_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/hubble/releases/download/$HUBBLE_VERSION/hubble-linux-${HUBBLE_ARCH}.tar.gz{,.sha256sum}
sha256sum --check hubble-linux-${HUBBLE_ARCH}.tar.gz.sha256sum
sudo tar xzvfC hubble-linux-${HUBBLE_ARCH}.tar.gz /usr/local/bin
rm hubble-linux-${HUBBLE_ARCH}.tar.gz{,.sha256sum}
```

Then check status

```sh
cilium status
```

### Access hubble

First port-forward

```sh
cilium hubble port-forward&
```

Then check status

```sh
hubble status
```

Then observe

```sh
hubble observe
# hubble observe -n default
```

### Access hubble ui

```sh
cilium hubble ui
```

## Demo

### Deploy demo app

```sh
kubectl create -f https://raw.githubusercontent.com/cilium/cilium/1.14.6/examples/minikube/http-sw-app.yaml
```

Result

```sh
service/deathstar created
deployment.apps/deathstar created
pod/tiefighter created
pod/xwing created
```

Check deployment

```sh
kubectl get pods,svc
```

Check cilium endpoints

```sh
# ALL should be 'Disabled'
kubectl -n kube-system get pods -l k8s-app=cilium
kubectl -n kube-system exec cilium-xxx -- cilium endpoint list
```

# Add Policy

```sh
kubectl exec xwing -- curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing
# Ship landed
kubectl exec tiefighter -- curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing
# Ship landed
```

No restriction

Create network policy

```yml
# rule1.yaml

apiVersion: 'cilium.io/v2'
kind: CiliumNetworkPolicy
metadata:
  name: 'rule1'
spec:
  description: 'L3-L4 policy to restrict deathstar access to empire ships only'
  endpointSelector:
    matchLabels:
      org: empire
      class: deathstar
  ingress:
    - fromEndpoints:
        - matchLabels:
            org: empire
      toPorts:
        - ports:
            - port: '80'
              protocol: TCP
```

```sh
kubectl apply -f rule1.yaml
# ciliumnetworkpolicy.cilium.io/rule1 created
```

Now check access again

```sh
kubectl exec tiefighter -- curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing
# Ship landed
kubectl exec xwing -- curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing
# ...
```

xwing request hangs.

Check policy

```sh
kubectl -n kube-system exec cilium-xxx -- cilium endpoint list
# deathstar pod should show 'Enabled'
```

Also check applied policy

```sh
kubectl describe cnp rule1
```

### Http-aware policy

Check access

```sh
kubectl exec tiefighter -- curl -s -XPUT deathstar.default.svc.cluster.local/v1/exhaust-port
# deathstar explodes (pod restarts)
```

```yml
# rule1-http.yaml

apiVersion: 'cilium.io/v2'
kind: CiliumNetworkPolicy
metadata:
  name: 'rule1'
spec:
  description: 'L7 policy to restrict access to specific HTTP call'
  endpointSelector:
    matchLabels:
      org: empire
      class: deathstar
  ingress:
    - fromEndpoints:
        - matchLabels:
            org: empire
      toPorts:
        - ports:
            - port: '80'
              protocol: TCP
          rules:
            http:
              - method: 'POST'
                path: '/v1/request-landing'
```

```sh
kubectl apply -f rule1-http.yaml
# ciliumnetworkpolicy.cilium.io/rule1 configured
```

Check access again

```sh
kubectl exec tiefighter -- curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing
# Ship landed (still works)
kubectl exec tiefighter -- curl -s -XPUT deathstar.default.svc.cluster.local/v1/exhaust-port
# Access denied (no explosion)
kubectl exec xwing -- curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing
# request hangs
```
