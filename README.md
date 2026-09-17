# devops-heros

DevOps coursework — Kubernetes, Sessions 9 through 12.

Every folder holds one session's `README.md` with, for each task: a one-line description of what it
does, the exact command that was run, and the **real terminal output** from running it, followed by
an explanation of what the output means. All manifests used are committed alongside.

## Sessions

| Session | Topic | Folder |
| --- | --- | --- |
| **9** | Kubernetes fundamentals & cluster architecture | [`session9-k8s/`](session9-k8s/) |
| **10** | Core objects, pod lifecycle & deployment strategies | [`session10-k8s-core-objects/`](session10-k8s-core-objects/) |
| **11** | Services & cluster networking | [`session-11-kubernetes-services/`](session-11-kubernetes-services/) |
| **12** | ConfigMaps, Secrets & Ingress | [`session-12-ingress-configmaps-secrets/`](session-12-ingress-configmaps-secrets/) |

## What each session covers

**Session 9** — minikube and kubectl installation, full cluster lifecycle (start / status / stop /
restart), and a write-up of the control plane and worker node components mapped onto the pods
actually running in the cluster.

**Session 10** — standalone pods, all twelve pod lifecycle states, readiness / liveness / startup
probes, init containers, sidecars, graceful termination, ReplicaSets, StatefulSets, DaemonSets,
rolling updates and rollbacks, two troubleshooting drills, and all four deployment strategies
(RollingUpdate, Blue-Green, Canary, Recreate) executed with measured traffic and a captured outage
window.

**Session 11** — all five Service types (ClusterIP, NodePort, LoadBalancer, ExternalName, Headless),
services without selectors, a CoreDNS and FQDN deep dive including the `ndots:5` latency problem, a
pod-identity comparison between Deployments and StatefulSets, a controller matrix, a cloud
cost-optimisation analysis, and the minikube docker-driver port-binding gotcha.

**Session 12** — ConfigMaps and the live-update/pod-immobility drill, Secrets and base64 mechanics
including the trailing-newline bug, enterprise secret management patterns, the NGINX Ingress
Controller, path-based / host-based / hybrid L7 routing, TLS termination, and end-to-end automation
scripts.

## Environment

| | |
| --- | --- |
| Cluster | minikube v1.39.0, `--driver=docker` |
| Kubernetes | v1.37.0 |
| Container runtime | containerd 2.3.4 |
| CNI | kindnet |
| Ingress | ingress-nginx v1.15.1 |
| Node IP | `192.168.49.2` |

## Reproducing

```bash
# bring up the cluster
minikube start --driver=docker
kubectl get nodes

# session 12 additionally needs the ingress controller
minikube addons enable ingress
kubectl wait --namespace ingress-nginx --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=120s

# then follow any session README from the top
cd session10-k8s-core-objects && kubectl apply -f pod.yml
```

Manifests are applied from their own session folder; each README shows the working directory in its
command blocks. Every lab cleans up after itself.
