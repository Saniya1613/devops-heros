# devops-heros

DevOps coursework — Linux, shell scripting, networking, Git, Docker and Kubernetes.

Every folder holds one topic's `README.md` with, for each task: a one-line description of what it
does, the exact command that was run, and the **real terminal output** from running it, followed by
an explanation of what the output means. All scripts, Dockerfiles and manifests are committed
alongside.

## Contents

| # | Topic | Folder |
| --- | --- | --- |
| 1 | Linux Fundamentals | [`01-linux-fundamentals/`](01-linux-fundamentals/) |
| 2 | Shell Scripting | [`02-shell-scripting/`](02-shell-scripting/) |
| 3 | Networking | [`03-networking/`](03-networking/) |
| 4 | Git and GitHub | [`04-git-and-github/`](04-git-and-github/) |
| 5 | Docker Fundamentals | [`05-docker-fundamentals/`](05-docker-fundamentals/) |
| 6 | Dockerfiles & Images | [`06-dockerfiles-and-images/`](06-dockerfiles-and-images/) |
| 7 | Docker Networking | [`07-docker-networking/`](07-docker-networking/) |
| 8 | Kubernetes Fundamentals | [`session9-k8s/`](session9-k8s/) |
| 9 | Kubernetes Pods, ReplicaSets & Deployments | [`session10-k8s-core-objects/`](session10-k8s-core-objects/) |
| 10 | Kubernetes Networking & Services | [`session-11-kubernetes-services/`](session-11-kubernetes-services/) |
| 11 | Kubernetes Ingress, ConfigMaps & Secrets | [`session-12-ingress-configmaps-secrets/`](session-12-ingress-configmaps-secrets/) |

The four Kubernetes folders keep the directory names the session briefs specified; the earlier topics
use numbered folders.

## What each topic covers

**1. Linux Fundamentals** — soft vs hard links traced by inode, `adduser` vs `useradd` compared
side by side, `journalctl` filtering, and a command reference.

**2. Shell Scripting** — a system information script using variables, `read -p` input, `mkdir` and
`touch`, and `>` output redirection to capture the running process list.

**3. Networking** — `ifconfig`, `ping`, `traceroute`, `netstat`/`ss`, `dig`/`nslookup`/`host`, `curl`
and `nc`, plus IP addressing notes and a troubleshooting order.

**4. Git and GitHub** — `git commit -m` vs `git commit -a -m`, and `git cherry-pick` including a
conflict resolved two ways.

**5. Docker Fundamentals** — five Hello World web apps (nginx, Apache, Python, Node.js, Java) built,
run on five ports, verified and cleaned up.

**6. Dockerfiles & Images** — the same Go service built with and without a multi-stage Dockerfile to
measure the difference, plus three application types deployed together with Compose.

**7. Docker Networking** — custom bridge networks and the isolation between them, the `host` driver,
bind mounts, named volumes, and a write-up of the `overlay` driver.

**8. Kubernetes Fundamentals** — minikube and kubectl setup, full cluster lifecycle, and the control
plane / worker node architecture mapped onto the pods actually running.

**9. Kubernetes Pods, ReplicaSets & Deployments** — all twelve pod lifecycle states, readiness /
liveness / startup probes, init containers, sidecars, graceful termination, ReplicaSets, StatefulSets,
DaemonSets, rolling updates and rollbacks, two troubleshooting drills, and all four deployment
strategies with measured traffic and a captured outage window.

**10. Kubernetes Networking & Services** — all five Service types, services without selectors, a
CoreDNS and FQDN deep dive including the `ndots:5` latency problem, a pod-identity comparison, a
controller matrix, cost optimisation, and the minikube docker-driver gotcha.

**11. Kubernetes Ingress, ConfigMaps & Secrets** — ConfigMaps and the live-update drill, Secrets and
the base64 trailing-newline bug, enterprise secret management, the NGINX Ingress Controller,
path / host / hybrid L7 routing, TLS termination, and end-to-end automation scripts.

## Environment

| | |
| --- | --- |
| OS | Ubuntu 24.04 |
| Docker | Engine 29.4.3 |
| Cluster | minikube v1.39.0, `--driver=docker` |
| Kubernetes | v1.37.0 |
| Container runtime | containerd 2.3.4 |
| CNI | kindnet |
| Ingress | ingress-nginx v1.15.1 |
| Node IP | `192.168.49.2` |

## Reproducing

Topics 1–7 need only Docker and standard Linux tooling. Topics 8–11 need a cluster:

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

Manifests are applied from their own topic folder; each README shows the working directory in its
command blocks. Every lab cleans up after itself.
