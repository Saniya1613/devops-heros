# Session 9 — Kubernetes Fundamentals & Cluster Architecture

Local single-node Kubernetes cluster built with **minikube** on the **docker** driver,
Kubernetes **v1.37.0**, container runtime **containerd 2.3.4**.

Every command below was actually executed and the terminal output is pasted verbatim.

---

## Task 1 — Verify the minikube and kubectl installation

**What this does:** confirms both CLIs are installed and reports their versions before anything else is attempted.

```bash
minikube version
kubectl version --client
docker --version
```

**Output**

```
minikube version: v1.39.0
commit: 7a9f6a841470a207de8cf4bafcccee0969d8ba10
Client Version: v1.37.0
Kustomize Version: v5.8.1
Docker version 29.4.3, build 055a478
```

`minikube` is the cluster provisioner; `kubectl` is the API client. They version independently —
kubectl is supported within one minor version either side of the cluster.

---

## Task 2 — Start the cluster and verify every component

**What this does:** boots the single-node control plane inside a Docker container and checks that the API server, kubelet and kubeconfig are all live.

```bash
minikube start --driver=docker
minikube status
```

**Output**

```
minikube
type: Control Plane
host: Running
kubelet: Running
apiserver: Running
kubeconfig: Configured

```

All four lines must read `Running` / `Configured`. If `apiserver` says `Stopped` while `host` says
`Running`, the node container is up but the control-plane static pods have not come online yet.

---

## Task 3 — Verify cluster endpoints and node health

**What this does:** asks the API server where the control plane and CoreDNS live, then confirms the node has registered and reached `Ready`.

```bash
kubectl cluster-info
kubectl get nodes
kubectl get nodes -o wide
```

**Output**

```
Kubernetes control plane is running at https://192.168.49.2:8443
CoreDNS is running at https://192.168.49.2:8443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
NAME       STATUS   ROLES           AGE     VERSION
minikube   Ready    control-plane   3m43s   v1.37.0
NAME       STATUS   ROLES           AGE     VERSION   INTERNAL-IP    EXTERNAL-IP   OS-IMAGE                         KERNEL-VERSION           CONTAINER-RUNTIME
minikube   Ready    control-plane   3m43s   v1.37.0   192.168.49.2   <none>        Debian GNU/Linux 12 (bookworm)   6.18.44-fc-v33 (amd64)   containerd://2.3.4
```

`ROLES: control-plane` confirms this node runs the control plane. In a single-node minikube cluster
the same node also accepts regular workloads, because minikube removes the usual
`node-role.kubernetes.io/control-plane:NoSchedule` taint.

---

## Task 4 — Confirm the control-plane pods are actually running

**What this does:** lists the system pods that *are* the control plane, so the architecture below is not just theory.

```bash
kubectl get pods -A
```

**Output**

```
NAMESPACE     NAME                               READY   STATUS    RESTARTS   AGE
kube-system   coredns-559f6c778d-kllk6           1/1     Running   0          3m34s
kube-system   etcd-minikube                      1/1     Running   0          3m40s
kube-system   kindnet-75dbk                      1/1     Running   0          87s
kube-system   kube-apiserver-minikube            1/1     Running   0          3m40s
kube-system   kube-controller-manager-minikube   1/1     Running   0          3m40s
kube-system   kube-proxy-7x4k6                   1/1     Running   0          3m35s
kube-system   kube-scheduler-minikube            1/1     Running   0          3m40s
kube-system   storage-provisioner                1/1     Running   0          3m39s
```

Mapping each pod to its architectural role:

| Pod | Role |
| --- | --- |
| `etcd-minikube` | cluster state store |
| `kube-apiserver-minikube` | the only component that talks to etcd |
| `kube-controller-manager-minikube` | runs the reconciliation loops |
| `kube-scheduler-minikube` | assigns pods to nodes |
| `kube-proxy` | programs node-level service routing |
| `coredns` | in-cluster DNS |
| `kindnet` | CNI plugin (pod networking) |
| `storage-provisioner` | dynamic PersistentVolume provisioning |

---

## Task 5 — Stop the cluster cleanly

**What this does:** shuts the node down gracefully and shows that the API server becomes unreachable, proving the control plane really lives inside that container.

```bash
minikube stop
minikube status
kubectl get nodes
```

**Output**

```
* Stopping node "minikube"  ...
* Powering off "minikube" via SSH ...
* 1 node stopped.
minikube
type: Control Plane
host: Stopped
kubelet: Stopped
apiserver: Stopped
kubeconfig: Stopped
The connection to the server localhost:8080 was refused - did you specify the right host or port?
```

With the node stopped, `kubectl` falls back to the default `localhost:8080` and the connection is
refused — there is no control plane left to answer.

---

## Task 6 — Restart the cluster

**What this does:** brings the same cluster back up; etcd state survives because the node container's volume persists.

```bash
minikube start --driver=docker
kubectl get nodes
```

**Output**

```
* minikube v1.39.0 on Ubuntu 24.04 (amd64)
* Using the docker driver based on existing profile
* Starting "minikube" primary control-plane node in "minikube" cluster
* Pulling base image v0.0.51 ...
* Preparing Kubernetes v1.37.0 on containerd 2.3.4 ...
* Verifying Kubernetes components...
  - Using image gcr.io/k8s-minikube/storage-provisioner:v5
* Enabled addons: storage-provisioner, default-storageclass
* Done! kubectl is now configured to use "minikube" cluster and "default" namespace by default

NAME       STATUS   ROLES           AGE     VERSION
minikube   Ready    control-plane   4m39s   v1.37.0
```

---

## Task 7 — Kubernetes architecture: Control Plane and Worker Node components

Written up from the [official Kubernetes architecture documentation](https://kubernetes.io/docs/concepts/architecture/).

### Control Plane (Master)

The control plane makes global decisions about the cluster and responds to cluster events. It does
not run application workloads.

| Component | What it does |
| --- | --- |
| **kube-apiserver** | The front door. Every read and write to cluster state goes through it — `kubectl`, controllers, kubelets, everything. It authenticates, authorises, validates against the schema, and is the **only** component permitted to talk to etcd. Horizontally scalable. |
| **etcd** | A consistent, highly-available key-value store holding the entire cluster state (every object's spec and status). If etcd is lost, the cluster is lost — this is what you back up. |
| **kube-scheduler** | Watches for Pods with no `nodeName` assigned and picks a node for each. It filters nodes that cannot run the Pod (resource requests, taints, node selectors, affinity), scores the survivors, then binds the Pod to the winner. It only *decides*; it never starts a container. |
| **kube-controller-manager** | Runs the reconciliation loops as a single binary. Each controller watches a resource and drives actual state toward desired state — Deployment controller creates ReplicaSets, ReplicaSet controller creates Pods, Node controller notices unresponsive nodes, Job controller runs batch work, and so on. |
| **cloud-controller-manager** | Only present on managed clouds. Talks to the provider API for LoadBalancer provisioning, node lifecycle and route setup. Absent on minikube, which is why `type: LoadBalancer` sits at `<pending>` until `minikube tunnel` emulates it. |

### Worker Node (Data Plane)

Worker nodes are where containers actually run.

| Component | What it does |
| --- | --- |
| **kubelet** | The node agent. It watches the API server for Pods bound to its node, tells the container runtime to start them, mounts volumes, runs liveness/readiness/startup probes, and reports Pod and Node status back. It only manages containers created by Kubernetes. |
| **Container runtime** | Does the real work of pulling images and running containers, via the CRI interface. Here it is **containerd 2.3.4** (Docker Engine is no longer used directly by kubelet). |
| **kube-proxy** | Implements the Service abstraction at the node level. It watches Services and EndpointSlices and programs iptables/IPVS rules so that traffic to a Service's virtual IP is load-balanced to a healthy backing Pod. |
| **CNI plugin** | Provides the pod network — assigns every Pod a routable cluster IP and makes pod-to-pod traffic work across nodes. Here it is **kindnet**, seen running as a DaemonSet in Task 4. |

### How a request flows through them

```
kubectl apply -f deployment.yaml
        │
        ▼
   kube-apiserver ──(persist)──► etcd
        │
        ├──► Deployment controller  ──► creates a ReplicaSet
        ├──► ReplicaSet controller  ──► creates N Pods (nodeName empty)
        ├──► kube-scheduler         ──► binds each Pod to a node
        │
        ▼
    kubelet on that node
        │
        ├──► CRI (containerd) ──► pull image, start container
        ├──► CNI (kindnet)    ──► attach pod to the network, assign IP
        └──► reports status back to kube-apiserver ──► etcd
```

Every component is a **watch loop on the API server** — nothing talks to anything else directly.
That is what makes the system self-healing: delete a Pod and the ReplicaSet controller notices the
gap on its next reconcile and creates a replacement, without anyone issuing a "recreate" command.

---

## Summary

| # | Task | Result |
| --- | --- | --- |
| 1 | Verify minikube + kubectl installation | minikube v1.39.0, kubectl v1.37.0 |
| 2 | Start cluster, verify components | host / kubelet / apiserver all Running |
| 3 | Verify endpoints and node health | node `minikube` Ready, control-plane role |
| 4 | Confirm control-plane pods | 8 system pods Running |
| 5 | Stop the cluster cleanly | API server unreachable, as expected |
| 6 | Restart the cluster | back to Ready, state preserved |
| 7 | Architecture write-up | control plane + worker node documented |
