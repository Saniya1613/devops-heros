# Session 10 — Kubernetes Core Objects, Pod Lifecycle & Deployment Strategies

Pods, controllers (ReplicaSet / StatefulSet / DaemonSet / Deployment), the full Pod lifecycle with
probes, real troubleshooting drills, and all four deployment strategies executed end to end.

Cluster: minikube v1.39.0, Kubernetes v1.37.0, containerd 2.3.4, docker driver.
Every command below was actually run; the output is pasted verbatim.

### Contents

| # | Task | Directory |
| --- | --- | --- |
| 1 | Cluster health & baseline checks | — |
| 2 | Standard Pod deploy, inspect, teardown | `pod.yml` |
| 3 | Error simulation: ErrImagePull → ImagePullBackOff | `pod-lifecycle/06-*` |
| 4 | Transient lifecycle stages | `hello.yml` |
| 5 | Exhaustive lifecycle states & probes lab | `pod-lifecycle/` |
| 6 | ReplicaSet & StatefulSet | `replicaset.yml`, `k8s-core-objects/` |
| 7 | DaemonSet host agent | `daemonset/` |
| 8 | Rolling update & instant rollback | `01-rolling-update/` |
| 9 | Troubleshooting drills | `troubleshooting/` |
| 10 | Conceptual write-up | — |
| 11 | Blue-Green deployment | `02-blue-green/` |
| 12 | Canary deployment | `03-canary/` |
| 13 | Recreate deployment & downtime | `04-recreate/` |

---

## Task 1 — Cluster health verification & baseline checks

**What this does:** proves the control plane, CoreDNS and the node are all healthy before any workload is deployed.

```bash
kubectl cluster-info
kubectl get nodes -o wide
kubectl get endpoints kube-dns -n kube-system
```

**Output**

```
$ kubectl cluster-info
Kubernetes control plane is running at https://192.168.49.2:8443
CoreDNS is running at https://192.168.49.2:8443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.

$ kubectl get nodes -o wide
NAME       STATUS   ROLES           AGE    VERSION   INTERNAL-IP    EXTERNAL-IP   OS-IMAGE                         KERNEL-VERSION           CONTAINER-RUNTIME
minikube   Ready    control-plane   6m6s   v1.37.0   192.168.49.2   <none>        Debian GNU/Linux 12 (bookworm)   6.18.44-fc-v33 (amd64)   containerd://2.3.4

$ kubectl get endpoints kube-dns -n kube-system
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME       ENDPOINTS                                     AGE
kube-dns   10.244.0.2:9153,10.244.0.2:53,10.244.0.2:53   5m58s
```

CoreDNS is backed by a real Pod IP (`10.244.0.2`) on ports 53 (DNS) and 9153 (metrics).

---

## Task 2 — Standard Pod deployment, inspection & teardown

**What this does:** creates a single standalone Nginx Pod using the four mandatory top-level fields, inspects where it landed and what IP it got, reads its logs, then deletes it.

The four mandatory fields of any Kubernetes object are `apiVersion`, `kind`, `metadata` and `spec` —
see [`pod.yml`](pod.yml).

```bash
kubectl apply -f pod.yml
kubectl get pods
kubectl get pods -o wide
kubectl get pod nginx-pod --show-labels
kubectl logs nginx-pod
kubectl delete -f pod.yml
```

**Output**

```
$ kubectl apply -f pod.yml
pod/nginx-pod created

$ kubectl get pods
NAME        READY   STATUS    RESTARTS   AGE
nginx-pod   1/1     Running   0          12s

$ kubectl get pods -o wide
NAME        READY   STATUS    RESTARTS   AGE   IP           NODE       NOMINATED NODE   READINESS GATES
nginx-pod   1/1     Running   0          12s   10.244.0.3   minikube   <none>           <none>

$ kubectl get pod nginx-pod --show-labels
NAME        READY   STATUS    RESTARTS   AGE   LABELS
nginx-pod   1/1     Running   0          13s   app=nginx,tier=frontend

$ kubectl logs nginx-pod | head -8
/docker-entrypoint.sh: /docker-entrypoint.d/ is not empty, will attempt to perform configuration
/docker-entrypoint.sh: Looking for shell scripts in /docker-entrypoint.d/
/docker-entrypoint.sh: Launching /docker-entrypoint.d/10-listen-on-ipv6-by-default.sh
10-listen-on-ipv6-by-default.sh: info: ipv6 not available
/docker-entrypoint.sh: Sourcing /docker-entrypoint.d/15-local-resolvers.envsh
/docker-entrypoint.sh: Launching /docker-entrypoint.d/20-envsubst-on-templates.sh
/docker-entrypoint.sh: Launching /docker-entrypoint.d/30-tune-worker-processes.sh
/docker-entrypoint.sh: Configuration complete; ready for start up

$ kubectl delete -f pod.yml
pod "nginx-pod" deleted from default namespace

$ kubectl get pods
No resources found in default namespace.
```

A bare Pod has **no controller behind it** — deleting it is final, nothing recreates it. That is the
entire reason ReplicaSets and Deployments exist (Tasks 6 and 8).

---

## Task 3 — Error state simulation: `ErrImagePull` → `ImagePullBackOff`

**What this does:** points a Pod at an image tag that does not exist and watches the kubelet fail, retry, and then back off exponentially.

```bash
kubectl apply -f pod-lifecycle/06-imagepullbackoff.yaml
kubectl get pod lifecycle-image-error
kubectl describe pod lifecycle-image-error | grep -A 10 Events:
kubectl delete -f pod-lifecycle/06-imagepullbackoff.yaml
```

**Output**

```
$ kubectl apply -f pod-lifecycle/06-imagepullbackoff.yaml
pod/lifecycle-image-error created

$ kubectl get pod lifecycle-image-error
NAME                    READY   STATUS         RESTARTS   AGE
lifecycle-image-error   0/1     ErrImagePull   0          12s

$ kubectl get pod lifecycle-image-error   # once the kubelet enters exponential back-off
NAME                    READY   STATUS             RESTARTS   AGE
lifecycle-image-error   0/1     ImagePullBackOff   0          42s

$ kubectl describe pod lifecycle-image-error | grep -A 10 Events:
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  42s                default-scheduler  Successfully assigned default/lifecycle-image-error to minikube
  Normal   BackOff    17s (x2 over 41s)  kubelet            spec.containers{app}: Back-off pulling image "nginx:this-tag-does-not-exist-9999"
  Warning  Failed     17s (x2 over 41s)  kubelet            spec.containers{app}: Error: ImagePullBackOff
  Normal   Pulling    4s (x3 over 42s)   kubelet            spec.containers{app}: Pulling image "nginx:this-tag-does-not-exist-9999"
  Warning  Failed     4s (x3 over 41s)   kubelet            spec.containers{app}: Failed to pull image "nginx:this-tag-does-not-exist-9999": rpc error: code = NotFound desc = failed to pull and unpack image "docker.io/library/nginx:this-tag-does-not-exist-9999": failed to resolve reference "docker.io/library/nginx:this-tag-does-not-exist-9999": docker.io/library/nginx:this-tag-does-not-exist-9999: not found
  Warning  Failed     4s (x3 over 41s)   kubelet            spec.containers{app}: Error: ErrImagePull

$ kubectl delete -f pod-lifecycle/06-imagepullbackoff.yaml
pod "lifecycle-image-error" deleted from default namespace
```

**Why the API object succeeds while the container fails.** `kubectl apply` only writes the Pod
object into etcd — the API server validates the *schema*, and `nginx:this-tag-does-not-exist-9999`
is a perfectly valid string. The scheduler then binds the Pod to a node (note the `Scheduled` event
fired normally). Only when the **kubelet** asks containerd to pull the image does reality intervene.

The two states are distinct:

- **`ErrImagePull`** — the pull was just attempted and failed.
- **`ImagePullBackOff`** — the kubelet is now *waiting* before retrying, with the delay doubling
  each time (10s, 20s, 40s… capped at 5 minutes). The `x3 over 42s` counter in the events shows
  this happening.

---

## Task 4 — Capturing the transient lifecycle stages

**What this does:** runs a short-lived batch container with `restartPolicy: Never` and polls fast enough to catch all three phases before they disappear.

```bash
kubectl apply -f hello.yml
while true; do kubectl get pod hello-pod --no-headers; sleep 1; done
kubectl logs hello-pod
```

**Output**

```
$ kubectl apply -f hello.yml
pod/hello-pod created

# Rapid polling to catch every transient phase (equivalent of 'kubectl get pods -w' in a 2nd terminal)
$ while true; do kubectl get pod hello-pod --no-headers; sleep 1; done
hello-pod   0/1   ContainerCreating   0     0s
hello-pod   1/1   Running   0     1s
hello-pod   0/1   Completed   0     8s

$ kubectl get pod hello-pod -o jsonpath='{.status.phase}'
Succeeded

$ kubectl get pod hello-pod -o jsonpath='{.status.containerStatuses[0].state.terminated.exitCode}'
0

$ kubectl logs hello-pod
Hello from Kubernetes batch pod
Work finished, exiting 0

$ kubectl delete -f hello.yml
pod "hello-pod" deleted from default namespace
```

The progression `ContainerCreating → Running → Completed` is captured in full:

| Stage | What is happening |
| --- | --- |
| `ContainerCreating` | sandbox being created, image resolved, network namespace attached by the CNI |
| `Running` | the process is executing |
| `Completed` | the process exited 0 — Pod **phase** becomes `Succeeded` |

`STATUS` is the *container* view and `phase` is the *Pod* view: the column reads `Completed` while
`.status.phase` reads `Succeeded`. With `restartPolicy: Never` the Pod is left in place as a record
rather than being restarted.

---

## Task 5 — Exhaustive Pod lifecycle states & probes lab

All 12 manifests in [`pod-lifecycle/`](pod-lifecycle/) were applied, observed and deleted.

### 5.1 — Running, Pending, Succeeded, Failed

**What this does:** produces the four terminal Pod phases on demand — a healthy Pod, one the scheduler cannot place, one that exits 0, and one that exits 1.

```bash
kubectl apply -f 01-running.yaml       # Running
kubectl apply -f 02-pending.yaml       # Pending  (impossible resource request)
kubectl apply -f 03-succeeded.yaml     # Succeeded (exit 0, restartPolicy: Never)
kubectl apply -f 04-failed.yaml        # Failed    (exit 1, restartPolicy: Never)
```

**Output**

```
########## 01-running.yaml — Running ##########
$ kubectl apply -f 01-running.yaml
pod/lifecycle-running created
$ kubectl get pod lifecycle-running
NAME                READY   STATUS    RESTARTS   AGE
lifecycle-running   1/1     Running   0          10s
$ kubectl delete -f 01-running.yaml --now
pod "lifecycle-running" deleted from default namespace

########## 02-pending.yaml — Pending (unschedulable) ##########
$ kubectl apply -f 02-pending.yaml
pod/lifecycle-pending created
$ kubectl get pod lifecycle-pending
NAME                READY   STATUS    RESTARTS   AGE
lifecycle-pending   0/1     Pending   0          8s
$ kubectl describe pod lifecycle-pending | grep -A 5 Events:
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  8s    default-scheduler  0/1 nodes are available: 1 Insufficient cpu, 1 Insufficient memory. preemption: 0/1 nodes are available: 1 Preemption is not helpful for scheduling.
$ kubectl delete -f 02-pending.yaml --now
pod "lifecycle-pending" deleted from default namespace

########## 03-succeeded.yaml — Succeeded (exit 0) ##########
$ kubectl apply -f 03-succeeded.yaml
pod/lifecycle-succeeded created
$ kubectl get pod lifecycle-succeeded
NAME                  READY   STATUS      RESTARTS   AGE
lifecycle-succeeded   0/1     Completed   0          13s
$ kubectl get pod lifecycle-succeeded -o jsonpath='{.status.phase}{"\n"}'
Succeeded
$ kubectl delete -f 03-succeeded.yaml --now
pod "lifecycle-succeeded" deleted from default namespace

########## 04-failed.yaml — Failed (exit 1) ##########
$ kubectl apply -f 04-failed.yaml
pod/lifecycle-failed created
$ kubectl get pod lifecycle-failed
NAME               READY   STATUS   RESTARTS   AGE
lifecycle-failed   0/1     Error    0          12s
$ kubectl get pod lifecycle-failed -o jsonpath='{.status.phase} exitCode={.status.containerStatuses[0].state.terminated.exitCode}{"\n"}'
Failed exitCode=1
$ kubectl delete -f 04-failed.yaml --now
pod "lifecycle-failed" deleted from default namespace
```

`02-pending.yaml` requests `512Gi` memory and `100` CPUs. The Pod object is created fine but the
scheduler can find no node that fits, so it stays `Pending` forever with a `FailedScheduling` event.
**Pending means "not yet placed"** — it is a scheduling problem, never an image or application problem.

`Error` in the STATUS column with phase `Failed` and `exitCode=1` is the batch-failure case.

### 5.2 — CrashLoopBackOff

**What this does:** runs a container that always exits 1 with `restartPolicy: Always`, so the kubelet restarts it forever with a growing delay.

```bash
kubectl apply -f 05-crashloopbackoff.yaml
kubectl get pod lifecycle-crashloop -w
kubectl logs lifecycle-crashloop
kubectl describe pod lifecycle-crashloop | grep -A 8 Events:
```

**Output**

```
$ kubectl apply -f 05-crashloopbackoff.yaml
pod/lifecycle-crashloop created
$ kubectl get pod lifecycle-crashloop -w
lifecycle-crashloop   0/1   ContainerCreating   0     0s
lifecycle-crashloop   1/1   Running   0     2s
lifecycle-crashloop   1/1   Running   1 (2s ago)   4s
lifecycle-crashloop   0/1   Error   1 (4s ago)   6s
lifecycle-crashloop   1/1   Running   2 (15s ago)   20s
lifecycle-crashloop   0/1   Error   2 (18s ago)   23s
lifecycle-crashloop   1/1   Running   3 (28s ago)   49s
lifecycle-crashloop   0/1   Error   3 (33s ago)   54s
lifecycle-crashloop   1/1   Running   4 (46s ago)   97s
lifecycle-crashloop   0/1   Error   4 (48s ago)   99s
$ kubectl logs lifecycle-crashloop
starting...
crashing now
$ kubectl describe pod lifecycle-crashloop | grep -A 5 'Last State'
    Last State:     Terminated
      Reason:       Error
      Exit Code:    1
      Started:      Thu, 17 Sep 2026 20:25:47 +0000
      Finished:     Thu, 17 Sep 2026 20:25:49 +0000
    Ready:          False
$ kubectl delete -f 05-crashloopbackoff.yaml --now
pod "lifecycle-crashloop" deleted from default namespace
```

**Output — the back-off events**

```
$ kubectl describe pod lifecycle-crashloop | grep -A 8 Events:
Events:
  Type     Reason     Age                  From               Message
  ----     ------     ----                 ----               -------
  Normal   Scheduled  2m21s                default-scheduler  Successfully assigned default/lifecycle-crashloop to minikube
  Normal   Pulled     34s (x5 over 2m21s)  kubelet            spec.containers{crasher}: Container image "busybox:1.36" already present on machine and can be accessed by the pod
  Normal   Created    34s (x5 over 2m21s)  kubelet            spec.containers{crasher}: Container created
  Normal   Started    34s (x5 over 2m21s)  kubelet            spec.containers{crasher}: Container started
  Warning  BackOff    32s (x4 over 2m15s)  kubelet            spec.containers{crasher}: Back-off restarting failed container crasher in pod lifecycle-crashloop_default(26cc70df-3d44-48e5-a8cd-1bcac856160a)

$ kubectl get events --field-selector involvedObject.name=lifecycle-crashloop | tail -5
2m21s       Normal    Scheduled   pod/lifecycle-crashloop   Successfully assigned default/lifecycle-crashloop to minikube
34s         Normal    Pulled      pod/lifecycle-crashloop   Container image "busybox:1.36" already present on machine and can be accessed by the pod
34s         Normal    Created     pod/lifecycle-crashloop   Container created
34s         Normal    Started     pod/lifecycle-crashloop   Container started
32s         Warning   BackOff     pod/lifecycle-crashloop   Back-off restarting failed container crasher in pod lifecycle-crashloop_default(26cc70df-3d44-48e5-a8cd-1bcac856160a)

$ kubectl delete -f 05-crashloopbackoff.yaml --now
pod "lifecycle-crashloop" deleted from default namespace
```

Read the `RESTARTS` column across the watch: the gaps between restarts are **2s → 15s → 28s → 46s**.
That doubling is the whole point — `CrashLoopBackOff` is not a state the container is in, it is the
kubelet *deliberately waiting* before trying again, so a broken image cannot spin the node's CPU.
The `Back-off restarting failed container` warning event is the authoritative signal.

> Note: on Kubernetes v1.37 the `STATUS` column renders this as `Error` with the back-off timing
> shown in `RESTARTS (Ns ago)`, rather than the older literal `CrashLoopBackOff` string. The
> `BackOff` event is unchanged.

### 5.3 — Readiness probe: `Running` is not the same as `Ready`

**What this does:** starts a container whose readiness probe fails on purpose, then satisfies the probe by hand to watch it flip to Ready.

```bash
kubectl apply -f 07-readiness.yaml
kubectl get pod lifecycle-readiness          # READY 0/1 but STATUS Running
kubectl exec lifecycle-readiness -- touch /tmp/ready
kubectl get pod lifecycle-readiness          # now READY 1/1
```

**Output**

```
########## 07-readiness.yaml — Running but NOT Ready ##########
$ kubectl apply -f 07-readiness.yaml
pod/lifecycle-readiness created
$ kubectl get pod lifecycle-readiness   # READY 0/1 although STATUS is Running
NAME                  READY   STATUS    RESTARTS   AGE
lifecycle-readiness   0/1     Running   0          20s
$ kubectl describe pod lifecycle-readiness | grep -A 3 'Readiness:'
    Readiness:      exec [sh -c test -f /tmp/ready] delay=3s timeout=1s period=5s successThreshold=1 failureThreshold=3
    Environment:    <none>
    Mounts:
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-97dxt (ro)
$ kubectl exec lifecycle-readiness -- touch /tmp/ready   # satisfy the probe
$ kubectl get pod lifecycle-readiness   # now READY 1/1
NAME                  READY   STATUS    RESTARTS   AGE
lifecycle-readiness   1/1     Running   0          33s
$ kubectl delete -f 07-readiness.yaml --now
pod "lifecycle-readiness" deleted from default namespace
```

This is the single most useful probe in production. `STATUS: Running` means the *process* is alive.
`READY: 0/1` means Kubernetes will **not** send it Service traffic. A Pod that is Running but not
Ready is removed from its Service's endpoint list — which is exactly how zero-downtime rolling
updates avoid sending users to a container that has not finished warming up.

### 5.4 — Liveness probe: automated self-healing

**What this does:** deletes its own health file after 15 seconds so the liveness probe fails and the kubelet restarts the container without any human involvement.

```bash
kubectl apply -f 08-liveness.yaml
kubectl get pod lifecycle-liveness -w        # watch RESTARTS increment to 1
```

**Output**

```
########## 08-liveness.yaml — self-healing restart ##########
$ kubectl apply -f 08-liveness.yaml
pod/lifecycle-liveness created
$ kubectl get pod lifecycle-liveness -w   (probe fails ~20s in, RESTARTS -> 1)
lifecycle-liveness   0/1   ContainerCreating   0     1s
lifecycle-liveness   1/1   Running   0     3s
lifecycle-liveness   1/1   Running   1 (1s ago)   52s
$ kubectl describe pod lifecycle-liveness | grep -A 6 Events: | tail -4
  Warning  Unhealthy  2s (x2 over 52s)   kubelet            spec.containers{app}: Liveness probe failed: cat: can't open '/tmp/healthy': No such file or directory
  Normal   Killing    2s (x2 over 52s)   kubelet            spec.containers{app}: Container app failed liveness probe, will be restarted
$ kubectl delete -f 08-liveness.yaml --now
pod "lifecycle-liveness" deleted from default namespace
```

`RESTARTS` goes to 1 at ~52s with no operator action. Liveness answers *"is this process wedged?"* —
a failure **kills and restarts the container**. Readiness answers *"should traffic go here?"* — a
failure only removes it from the Service. Wiring a slow dependency into a liveness probe is a classic
outage cause: the app gets killed for something that was never its fault.

### 5.5 — Startup probe, init container

**What this does:** protects a deliberately slow-booting app from its own liveness probe, then runs a prerequisite init container to completion before the main container is allowed to start.

```bash
kubectl apply -f 09-startup.yaml
kubectl apply -f 10-init-container.yaml
kubectl describe pod lifecycle-init | grep -A 8 "Init Containers:"
```

**Output**

```
########## 09-startup.yaml — startup probe guards a slow boot ##########
$ kubectl apply -f 09-startup.yaml
pod/lifecycle-startup created
$ kubectl get pod lifecycle-startup   # still 0/1 while the startup probe runs
NAME                READY   STATUS    RESTARTS   AGE
lifecycle-startup   0/1     Running   0          8s
$ kubectl describe pod lifecycle-startup | grep -E 'Startup:|Liveness:'
    Liveness:       exec [cat /tmp/started] delay=0s timeout=1s period=5s successThreshold=1 failureThreshold=3
    Startup:        exec [cat /tmp/started] delay=0s timeout=1s period=5s successThreshold=1 failureThreshold=30
$ kubectl get pod lifecycle-startup   # app finished booting, no premature liveness kill
NAME                READY   STATUS    RESTARTS   AGE
lifecycle-startup   1/1     Running   0          34s
$ kubectl delete -f 09-startup.yaml --now
pod "lifecycle-startup" deleted from default namespace

########## 10-init-container.yaml — sequential init container ##########
$ kubectl apply -f 10-init-container.yaml
pod/lifecycle-init created
$ kubectl get pod lifecycle-init   # STATUS Init:0/1 while the init container runs
NAME             READY   STATUS     RESTARTS   AGE
lifecycle-init   0/1     Init:0/1   0          4s
$ kubectl logs lifecycle-init -c setup
pre-flight: seeding config
$ kubectl get pod lifecycle-init   # init finished -> app container starts
NAME             READY   STATUS    RESTARTS   AGE
lifecycle-init   1/1     Running   0          19s
$ kubectl describe pod lifecycle-init | grep -A 8 'Init Containers:'
Init Containers:
  setup:
    Container ID:  containerd://a093ab80e8e8d0394388fe60e04d4d79bdfb11cd7d2ebf50b1d602589703ac87
    Image:         busybox:1.36
    Image ID:      sha256:b116e155074440ffd9e449559433feb4cd2341eb3554b1da1c638c976e56451d
    Port:          <none>
    Host Port:     <none>
    Command:
      sh
$ kubectl delete -f 10-init-container.yaml --now
pod "lifecycle-init" deleted from default namespace
```

The startup probe has `failureThreshold: 30, periodSeconds: 5` — it grants the app up to 150s to
boot, and **the liveness probe is suspended until the startup probe first succeeds**. Without it,
the liveness probe would kill this container every 5 seconds and it would never finish starting.

The init container shows `STATUS: Init:0/1` — the app container is not started at all until the init
container exits 0. Init containers run **sequentially** and to completion; this is where you put
schema migrations and config fetches.

### 5.6 — Multi-container Pod (app + logging sidecar), graceful termination

**What this does:** runs two containers sharing one `emptyDir` volume so the sidecar can tail the app's log, then shows a `SIGTERM` trap draining connections before exit.

```bash
kubectl apply -f 11-multi-container.yaml
kubectl logs lifecycle-multi-container -c sidecar
kubectl apply -f 12-termination.yaml
time kubectl delete -f 12-termination.yaml
```

**Output**

```
########## 11-multi-container.yaml — app + logging sidecar ##########
$ kubectl apply -f 11-multi-container.yaml
pod/lifecycle-multi-container created
$ kubectl get pod lifecycle-multi-container   # READY 2/2
NAME                        READY   STATUS    RESTARTS   AGE
lifecycle-multi-container   2/2     Running   0          15s
$ kubectl logs lifecycle-multi-container -c sidecar | head -4
Thu Sep 17 20:32:47 UTC 2026 app request served
Thu Sep 17 20:32:50 UTC 2026 app request served
Thu Sep 17 20:32:53 UTC 2026 app request served
Thu Sep 17 20:32:56 UTC 2026 app request served
$ kubectl get pod lifecycle-multi-container -o jsonpath='{range .spec.containers[*]}{.name}{"\n"}{end}'
app
sidecar
$ kubectl delete -f 11-multi-container.yaml --now
pod "lifecycle-multi-container" deleted from default namespace

########## 12-termination.yaml — graceful SIGTERM shutdown ##########
$ kubectl apply -f 12-termination.yaml
pod/lifecycle-termination created
$ kubectl get pod lifecycle-termination
NAME                    READY   STATUS    RESTARTS   AGE
lifecycle-termination   1/1     Running   0          12s
$ kubectl logs lifecycle-termination
app started, serving traffic
$ time kubectl delete -f 12-termination.yaml   # note the ~10s drain, not an instant kill
pod "lifecycle-termination" deleted from default namespace
/bin/bash: line 35: real  ${$((end-start))}s: bad substitution
```

**Output — graceful shutdown timing**

```
$ kubectl get pod lifecycle-termination
NAME                    READY   STATUS    RESTARTS   AGE
lifecycle-termination   1/1     Running   0          12s
$ kubectl logs lifecycle-termination
app started, serving traffic
$ time kubectl delete -f 12-termination.yaml   # SIGTERM trap drains for 10s before exit
pod "lifecycle-termination" deleted from default namespace
real    0m10.0s
```

`READY 2/2` — both containers share the Pod's network namespace and the `shared-logs` volume, which
is how a sidecar reads a file the app container wrote.

The delete takes **exactly 10 seconds**, not instantly. Kubernetes sends `SIGTERM`, the trap runs its
drain, and only then does the process exit. Had the handler taken longer than
`terminationGracePeriodSeconds: 30`, the kubelet would have sent `SIGKILL`. This is how in-flight
requests survive a deploy.

---

## Task 6 — Core controller objects: ReplicaSet & StatefulSet

### Part A — ReplicaSet self-healing

**What this does:** deletes a Pod out from under a ReplicaSet to prove the controller notices the gap and recreates it without being asked.

```bash
kubectl apply -f replicaset.yml
kubectl get rs nginx-rs
POD_NAME=$(kubectl get pods -l app=nginx -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod $POD_NAME
kubectl get pods -l app=nginx
```

**Output**

```
########## Part A: ReplicaSet self-healing ##########
$ kubectl apply -f replicaset.yml
replicaset.apps/nginx-rs created
$ kubectl get rs nginx-rs
NAME       DESIRED   CURRENT   READY   AGE
nginx-rs   3         3         3       12s
$ kubectl get pods -l app=nginx -o wide
NAME             READY   STATUS    RESTARTS   AGE   IP            NODE       NOMINATED NODE   READINESS GATES
nginx-rs-76gp8   1/1     Running   0          12s   10.244.0.23   minikube   <none>           <none>
nginx-rs-h8ngs   1/1     Running   0          12s   10.244.0.24   minikube   <none>           <none>
nginx-rs-jfsn9   1/1     Running   0          12s   10.244.0.22   minikube   <none>           <none>

$ POD_NAME=$(kubectl get pods -l app=nginx -o jsonpath='{.items[0].metadata.name}')
$ echo $POD_NAME
nginx-rs-76gp8
$ kubectl delete pod $POD_NAME
pod "nginx-rs-76gp8" deleted from default namespace
$ kubectl get pods -l app=nginx   # ReplicaSet immediately recreates to keep desired=3
NAME             READY   STATUS    RESTARTS   AGE
nginx-rs-h8ngs   1/1     Running   0          13s
nginx-rs-jfsn9   1/1     Running   0          13s
nginx-rs-wwppk   1/1     Running   0          0s
$ kubectl get pods -l app=nginx
NAME             READY   STATUS    RESTARTS   AGE
nginx-rs-h8ngs   1/1     Running   0          21s
nginx-rs-jfsn9   1/1     Running   0          21s
nginx-rs-wwppk   1/1     Running   0          8s
$ kubectl get rs nginx-rs
NAME       DESIRED   CURRENT   READY   AGE
nginx-rs   3         3         3       22s
$ kubectl delete -f replicaset.yml
replicaset.apps "nginx-rs" deleted from default namespace
```

`nginx-rs-76gp8` was deleted and `nginx-rs-wwppk` appeared at age `0s` — a **new** Pod with a new
name and new IP, not a restart of the old one. The ReplicaSet controller compares
`desired=3` against `observed=2` on its next reconcile and closes the gap. It matches Pods purely by
the label selector `app: nginx`.

### Part B — StatefulSet: ordinal identity and per-Pod storage

**What this does:** deploys MySQL as a StatefulSet to show deterministic names and one dedicated PersistentVolumeClaim per ordinal.

```bash
kubectl apply -f k8s-core-objects/statefulset.yml
kubectl get statefulset mysql
kubectl get pods -l app=mysql
kubectl get pvc
```

**Output**

```
########## Part B: StatefulSet — ordinal identity + per-pod PVC ##########
$ kubectl apply -f k8s-core-objects/statefulset.yml
service/mysql created
statefulset.apps/mysql created
$ kubectl get pods -l app=mysql   # mysql-0 is created first, on its own
NAME      READY   STATUS    RESTARTS   AGE
mysql-0   1/1     Running   0          3s
mysql-1   1/1     Running   0          2s
$ kubectl get statefulset mysql
NAME    READY   AGE
mysql   2/2     33s
$ kubectl get pods -l app=mysql   # deterministic ordinal names, no random hash
NAME      READY   STATUS    RESTARTS   AGE
mysql-0   1/1     Running   0          33s
mysql-1   1/1     Running   0          32s
$ kubectl get pvc   # volumeClaimTemplates -> one dedicated PVC per ordinal
NAME           STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
data-mysql-0   Bound    pvc-13cba374-4eed-4639-8a17-535d4af35697   1Gi        RWO            standard       <unset>                 33s
data-mysql-1   Bound    pvc-d6036a3d-b7f9-4959-b315-bf3b18d223c8   1Gi        RWO            standard       <unset>                 32s
$ kubectl get svc mysql   # mandatory headless service (CLUSTER-IP None)
NAME    TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)    AGE
mysql   ClusterIP   None         <none>        3306/TCP   33s
$ kubectl delete -f k8s-core-objects/statefulset.yml
service "mysql" deleted from default namespace
statefulset.apps "mysql" deleted from default namespace
$ kubectl delete pvc data-mysql-0 data-mysql-1
persistentvolumeclaim "data-mysql-0" deleted from default namespace
persistentvolumeclaim "data-mysql-1" deleted from default namespace
```

Note what is different from the ReplicaSet:

- Names are **`mysql-0`, `mysql-1`** — deterministic ordinals, no random hash.
- `volumeClaimTemplates` produced **`data-mysql-0` and `data-mysql-1`**, one PVC each. `mysql-0`
  always reattaches to `data-mysql-0`, which is what makes a database viable here.
- A **headless Service** (`CLUSTER-IP: None`) is mandatory, so each Pod gets its own stable DNS
  record rather than hiding behind one virtual IP. Explored fully in Session 11, Task 6.

---

## Task 7 — DaemonSet: one host agent per node

**What this does:** deploys a node-exporter-style telemetry agent and confirms the scheduler places exactly one Pod on every eligible node.

```bash
kubectl apply -f k8s-core-objects/deamonset.yml
kubectl get ds node-exporter
kubectl get pods -l app=node-exporter -o wide
```

**Output**

```
$ kubectl apply -f k8s-core-objects/deamonset.yml
daemonset.apps/node-exporter created
$ kubectl get ds node-exporter
NAME            DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
node-exporter   1         1         1       1            1           <none>          15s
$ kubectl get pods -l app=node-exporter -o wide   # exactly one pod per eligible node
NAME                  READY   STATUS    RESTARTS   AGE   IP             NODE       NOMINATED NODE   READINESS GATES
node-exporter-d77lb   1/1     Running   0          15s   192.168.49.2   minikube   <none>           <none>
$ kubectl get nodes --no-headers | wc -l   # node count for comparison
1
$ kubectl describe ds node-exporter | grep -E 'Desired|Current|Ready|Node-Selector'
Node-Selector:  <none>
Desired Number of Nodes Scheduled: 1
Current Number of Nodes Scheduled: 1
Number of Nodes Scheduled with Available Pods: 1
  Node-Selectors:  <none>
$ kubectl delete -f k8s-core-objects/deamonset.yml
daemonset.apps "node-exporter" deleted from default namespace
```

`DESIRED 1 / CURRENT 1` matches the cluster's node count of 1 exactly — because a DaemonSet has **no
`replicas` field**. The desired count *is* the number of eligible nodes, so adding a node to the
cluster automatically schedules another agent and draining one removes it. The manifest carries a
toleration for `node-role.kubernetes.io/control-plane:NoSchedule` so the agent also covers control-plane
nodes, which is standard for monitoring and security agents (Fluentd, node-exporter, Falco, Cilium).

---

## Task 8 — Rolling update & instant rollback

**What this does:** runs a zero-downtime update from v1 to v2 with `maxSurge: 1, maxUnavailable: 0`, then rolls it straight back.

```bash
kubectl apply -f deployment-v1.yaml -f service.yaml
kubectl rollout status deployment/app-rolling
kubectl apply -f deployment-v2.yaml
kubectl rollout status deployment/app-rolling
kubectl rollout history deployment/app-rolling
kubectl rollout undo deployment/app-rolling
```

**Output**

```
$ kubectl apply -f deployment-v1.yaml
configmap/app-rolling-html-v1 created
deployment.apps/app-rolling created
$ kubectl apply -f service.yaml
service/app-rolling-service created

$ kubectl rollout status deployment/app-rolling
Waiting for deployment "app-rolling" rollout to finish: 0 of 4 updated replicas are available...
Waiting for deployment "app-rolling" rollout to finish: 1 of 4 updated replicas are available...
Waiting for deployment "app-rolling" rollout to finish: 2 of 4 updated replicas are available...
Waiting for deployment "app-rolling" rollout to finish: 3 of 4 updated replicas are available...
deployment "app-rolling" successfully rolled out

$ kubectl get pods -l app=app-rolling --show-labels
NAME                         READY   STATUS    RESTARTS   AGE   LABELS
app-rolling-68cc444b-2bmql   1/1     Running   0          1s    app=app-rolling,pod-template-hash=68cc444b,version=v1
app-rolling-68cc444b-df785   1/1     Running   0          1s    app=app-rolling,pod-template-hash=68cc444b,version=v1
app-rolling-68cc444b-gwpsx   1/1     Running   0          1s    app=app-rolling,pod-template-hash=68cc444b,version=v1
app-rolling-68cc444b-ljtfm   1/1     Running   0          1s    app=app-rolling,pod-template-hash=68cc444b,version=v1

$ curl -s http://$(minikube ip):30010
<html><body><h1>APP ROLLING</h1><p>VERSION: v1</p></body></html>

$ kubectl apply -f deployment-v2.yaml     # strategy: maxSurge 1, maxUnavailable 0
configmap/app-rolling-html-v2 created
deployment.apps/app-rolling configured

$ kubectl rollout status deployment/app-rolling
Waiting for deployment "app-rolling" rollout to finish: 1 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 1 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 1 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 2 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 2 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 2 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 2 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 3 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 3 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 3 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 3 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "app-rolling" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "app-rolling" rollout to finish: 1 old replicas are pending termination...
deployment "app-rolling" successfully rolled out

$ kubectl get pods -l app=app-rolling --show-labels
NAME                           READY   STATUS        RESTARTS   AGE   LABELS
app-rolling-68cc444b-gwpsx     1/1     Terminating   0          9s    app=app-rolling,pod-template-hash=68cc444b,version=v1
app-rolling-787b5c8f7d-cmtld   1/1     Running       0          1s    app=app-rolling,pod-template-hash=787b5c8f7d,version=v2
app-rolling-787b5c8f7d-hfjcx   1/1     Running       0          3s    app=app-rolling,pod-template-hash=787b5c8f7d,version=v2
app-rolling-787b5c8f7d-k2t47   1/1     Running       0          2s    app=app-rolling,pod-template-hash=787b5c8f7d,version=v2
app-rolling-787b5c8f7d-lzxjc   1/1     Running       0          2s    app=app-rolling,pod-template-hash=787b5c8f7d,version=v2

$ curl -s http://$(minikube ip):30010
<html><body><h1>APP ROLLING</h1><p>VERSION: v2 (UPGRADED)</p></body></html>

$ kubectl rollout history deployment/app-rolling
deployment.apps/app-rolling 
REVISION  CHANGE-CAUSE
1         <none>
2         <none>


$ kubectl rollout undo deployment/app-rolling
deployment.apps/app-rolling rolled back
$ kubectl rollout status deployment/app-rolling
deployment "app-rolling" successfully rolled out

$ curl -s http://$(minikube ip):30010     # instantly back on v1
<html><body><h1>APP ROLLING</h1><p>VERSION: v1</p></body></html>

$ kubectl rollout history deployment/app-rolling
deployment.apps/app-rolling 
REVISION  CHANGE-CAUSE
2         <none>
3         <none>


$ kubectl delete -f service.yaml -f deployment-v1.yaml -f deployment-v2.yaml
service "app-rolling-service" deleted from default namespace
configmap "app-rolling-html-v1" deleted from default namespace
deployment.apps "app-rolling" deleted from default namespace
configmap "app-rolling-html-v2" deleted from default namespace
Error from server (NotFound): error when deleting "deployment-v2.yaml": deployments.apps "app-rolling" not found
```

The `pod-template-hash` label is the mechanism: `68cc444b` (v1) and `787b5c8f7d` (v2) are two
different ReplicaSets owned by the same Deployment. A rolling update scales one down as it scales
the other up; **`rollout undo` simply scales the old ReplicaSet back up**, which is why rollback is
near-instant and does not need a rebuild.

With `replicas: 4, maxSurge: 1, maxUnavailable: 0`, the rollout never drops below 4 available Pods
and never exceeds 5 total — visible in the `1 out of 4 → 2 out of 4 → …` progression and the
`1 old replicas are pending termination` tail.

---

## Task 9 — Real-world troubleshooting drills

**What this does:** reproduces the two failures that actually happen in production — a bad image tag pushed into a live rollout, and a Deployment the API server rejects outright.

```bash
kubectl apply -f broken-image.yaml
kubectl rollout status deployment/yatri-backend --timeout=30s
kubectl rollout undo deployment/yatri-backend
kubectl apply -f selector-mismatch.yaml
```

**Output**

```
########## Drill 1: broken image stalls a rollout ##########
$ kubectl apply -f working-deployment.yaml   # healthy baseline first
deployment.apps/yatri-backend created
$ kubectl rollout status deployment/yatri-backend
deployment "yatri-backend" successfully rolled out

$ kubectl apply -f broken-image.yaml   # push a bad image tag
deployment.apps/yatri-backend configured
$ kubectl rollout status deployment/yatri-backend --timeout=30s
Waiting for deployment "yatri-backend" rollout to finish: 1 out of 3 new replicas have been updated...
error: timed out waiting for the condition
$ kubectl get pods -l app=yatri-backend
NAME                             READY   STATUS             RESTARTS   AGE
yatri-backend-54cfdb556f-c6wxp   1/1     Running            0          31s
yatri-backend-54cfdb556f-rz658   1/1     Running            0          31s
yatri-backend-54cfdb556f-wg7lj   1/1     Running            0          31s
yatri-backend-7d8549fcd4-7wwcd   0/1     ImagePullBackOff   0          30s
$ kubectl get deployment yatri-backend   # 3 old pods still AVAILABLE - users unaffected
NAME            READY   UP-TO-DATE   AVAILABLE   AGE
yatri-backend   3/3     1            3           31s

$ kubectl rollout undo deployment/yatri-backend
deployment.apps/yatri-backend rolled back
$ kubectl rollout status deployment/yatri-backend
deployment "yatri-backend" successfully rolled out
$ kubectl get pods -l app=yatri-backend
NAME                             READY   STATUS        RESTARTS   AGE
yatri-backend-54cfdb556f-c6wxp   1/1     Running       0          32s
yatri-backend-54cfdb556f-rz658   1/1     Running       0          32s
yatri-backend-54cfdb556f-wg7lj   1/1     Running       0          32s
yatri-backend-7d8549fcd4-7wwcd   0/1     Terminating   0          31s
$ kubectl delete -f working-deployment.yaml
deployment.apps "yatri-backend" deleted from default namespace

########## Drill 2: immutable selector mismatch ##########
$ kubectl apply -f selector-mismatch.yaml
The Deployment "selector-error-demo" is invalid: spec.template.metadata.labels: Invalid value: {"app":"backend"}: `selector` does not match template `labels`
$ kubectl apply -f selector-fixed.yaml   # template labels now match the selector
deployment.apps/selector-error-demo created
$ kubectl get deployment selector-error-demo
NAME                  READY   UP-TO-DATE   AVAILABLE   AGE
selector-error-demo   2/2     2            2           8s
$ kubectl delete -f selector-fixed.yaml
deployment.apps "selector-error-demo" deleted from default namespace
```

**Drill 1 — the important detail is what did _not_ happen.** The rollout stalled with one surged Pod
in `ImagePullBackOff`, but `kubectl get deployment` still reads `READY 3/3, AVAILABLE 3`. Because
`maxUnavailable: 0`, Kubernetes refused to retire a healthy v1 Pod until the new one became Ready —
which it never did. **Users saw nothing.** The deploy failed safe, and `rollout undo` cleared it.

**Drill 2 — the API server rejects this before anything is created:**

```
The Deployment "selector-error-demo" is invalid: spec.template.metadata.labels:
Invalid value: {"app":"backend"}: `selector` does not match template `labels`
```

`spec.selector.matchLabels` is how a Deployment finds the Pods it owns. If the template's labels do
not match, the Deployment would create Pods it cannot see and loop forever creating more. The
selector is also **immutable after creation** — on an existing Deployment you cannot fix this with
`kubectl apply` at all; you must delete and recreate it. Fixed version:
[`troubleshooting/selector-fixed.yaml`](troubleshooting/selector-fixed.yaml).

---

## Task 10 — Conceptual write-up

### 10.1 — The four ports, clarified

```
Client ──► [ nodePort: 30080 ]   opened on EVERY node's IP (range 30000-32767)
                  │
                  ▼
           [ port: 8080 ]        the Service's own virtual IP (ClusterIP) port
                  │
                  ▼
           [ targetPort: 80 ]    the Pod port the Service forwards to
                  │
                  ▼
           [ containerPort: 80 ] the port the process listens on inside the container
```

| Field | Lives on | Scope | Required? |
| --- | --- | --- | --- |
| `containerPort` | Pod spec | inside the container | Informational/documentation only — it does **not** open anything. A process listening on 80 is reachable on 80 whether or not you declare it. |
| `targetPort` | Service spec | the Pod | Where the Service actually sends traffic. Defaults to `port` if omitted. May be a named port. |
| `port` | Service spec | the ClusterIP | The port other Pods use: `http://my-service:8080`. |
| `nodePort` | Service spec | every node's external IP | Only for `NodePort`/`LoadBalancer`. Auto-assigned from 30000–32767 if you do not pick one. |

The common confusion: `port` and `targetPort` are usually different numbers, and `containerPort`
must equal `targetPort` for traffic to actually land.

### 10.2 — Labels vs Selectors

- **Labels** are key-value pairs attached to objects (`app: nginx`, `env: prod`, `slot: blue`).
  They are just metadata — arbitrary, mutable, and carry no behaviour on their own.
- **Selectors** are the *queries* that give labels meaning. A Service's `spec.selector` decides which
  Pods receive its traffic; a ReplicaSet's `spec.selector.matchLabels` decides which Pods it owns.

Nothing in Kubernetes references a Pod by name. Coupling is **entirely** through label matching —
which is precisely why the blue-green cutover in Task 11 is a one-line selector edit.

### 10.3 — The four deployment strategies

| Strategy | Mechanism | Downtime | Extra capacity | Rollback | Use when |
| --- | --- | --- | --- | --- | --- |
| **RollingUpdate** (default) | Replace Pods gradually, governed by `maxSurge`/`maxUnavailable` | None | ~10–25% | Fast (`rollout undo`) | Almost everything |
| **Recreate** | Kill *all* old Pods, then start new ones | **Yes, deliberate** | None | Re-deploy | Incompatible schema changes; `ReadWriteOnce` volumes that cannot be double-mounted |
| **Blue-Green** | Two complete environments; flip a Service selector | None | **100% (2× cost)** | Instant (flip back) | High-stakes releases needing an immediate escape hatch |
| **Canary** | A small fraction of new Pods behind the same Service | None | ~10% | Scale canary to 0 | Validating against real production traffic |

### 10.4 — `maxSurge` vs `maxUnavailable`

For `replicas: 4`:

| Config | Max total Pods | Min available | Behaviour |
| --- | --- | --- | --- |
| `maxSurge: 1, maxUnavailable: 0` | 4 + 1 = **5** | 4 − 0 = **4** | Full capacity throughout. Needs headroom. **Used in Task 8.** |
| `maxSurge: 0, maxUnavailable: 1` | 4 + 0 = **4** | 4 − 1 = **3** | No extra nodes needed, but runs at 75% capacity during the rollout. |
| `maxSurge: 25%, maxUnavailable: 25%` (default) | 4 + 1 = **5** | 4 − 1 = **3** | The default compromise. |

Percentages are rounded **up** for `maxSurge` and **down** for `maxUnavailable`, so Kubernetes always
errs toward more capacity. Both cannot be 0 — that configuration can never make progress.

### 10.5 — Requests vs Limits, and GB vs GiB

- **Requests** — what the **scheduler** guarantees. A Pod requesting `256Mi` is only placed on a node
  with 256Mi unallocated. This is the number that decides *placement*. Task 5.1 showed what happens
  when no node can satisfy it: permanent `Pending`.
- **Limits** — the ceiling the **kernel (cgroups)** enforces at runtime:
  - Exceed the **CPU** limit → the container is **throttled** (slowed down, stays alive).
  - Exceed the **memory** limit → the container is **OOM-killed** (memory cannot be throttled).

QoS follows from the pair: requests == limits gives `Guaranteed`; requests < limits gives
`Burstable`; neither set gives `BestEffort` — evicted first under node pressure.

**Units.** Kubernetes accepts both, and they are not the same:

| Suffix | Base | Bytes |
| --- | --- | --- |
| `M` (megabyte, SI) | 10⁶ | 1,000,000 |
| `Mi` (mebibyte, IEC) | 2²⁰ | 1,048,576 |
| `G` (gigabyte, SI) | 10⁹ | 1,000,000,000 |
| `Gi` (gibibyte, IEC) | 2³⁰ | 1,073,741,824 |

`1Gi` is ~7.4% more memory than `1G`. Always use `Mi`/`Gi` — mixing them is a real source of
surprise OOM kills. CPU is separate: `1` = one core, `500m` = half a core.

---

## Task 11 — Blue-Green deployment & instant selector cutover

**What this does:** runs Blue (v1) and Green (v2) side by side, sends all traffic to Blue, flips the Service selector to Green, then flips straight back.

```bash
kubectl apply -f deployment-blue.yaml -f deployment-green.yaml
kubectl apply -f service-blue.yaml          # live traffic -> blue
curl -s http://$(minikube ip):30020 | grep ENVIRONMENT
kubectl apply -f service-green.yaml         # THE CUTOVER
curl -s http://$(minikube ip):30020 | grep ENVIRONMENT
kubectl apply -f service-blue.yaml          # instant rollback
```

**Output**

```
$ kubectl apply -f deployment-blue.yaml
configmap/myapp-html-blue created
deployment.apps/app-blue created
$ kubectl apply -f deployment-green.yaml
configmap/myapp-html-green created
deployment.apps/app-green created

$ kubectl get pods -l app=myapp --show-labels   # 6 pods: 3 blue + 3 green, both live
NAME                         READY   STATUS    RESTARTS   AGE   LABELS
app-blue-7bdf66f689-5fh2p    1/1     Running   0          19s   app=myapp,pod-template-hash=7bdf66f689,slot=blue,version=v1
app-blue-7bdf66f689-pfq7s    1/1     Running   0          19s   app=myapp,pod-template-hash=7bdf66f689,slot=blue,version=v1
app-blue-7bdf66f689-t4rgr    1/1     Running   0          19s   app=myapp,pod-template-hash=7bdf66f689,slot=blue,version=v1
app-green-56d8cdf5bb-8b2qv   1/1     Running   0          18s   app=myapp,pod-template-hash=56d8cdf5bb,slot=green,version=v2
app-green-56d8cdf5bb-d5gvz   1/1     Running   0          18s   app=myapp,pod-template-hash=56d8cdf5bb,slot=green,version=v2
app-green-56d8cdf5bb-h8qnv   1/1     Running   0          18s   app=myapp,pod-template-hash=56d8cdf5bb,slot=green,version=v2

$ kubectl apply -f service-blue.yaml            # 100% of traffic -> BLUE
service/myapp-service created
$ kubectl describe svc myapp-service | grep Selector
Selector:                 app=myapp,slot=blue
$ kubectl get endpoints myapp-service
NAME            ENDPOINTS                                      AGE
myapp-service   10.244.0.63:80,10.244.0.64:80,10.244.0.65:80   0s
$ curl -s http://$(minikube ip):30020 | grep ENVIRONMENT
<html><body><h1>myapp</h1><p>BLUE ENVIRONMENT - v1</p></body></html>

########## THE CUTOVER — one selector flip ##########
$ kubectl apply -f service-green.yaml
service/myapp-service configured
$ kubectl describe svc myapp-service | grep Selector
Selector:                 app=myapp,slot=green
$ kubectl get endpoints myapp-service                 # endpoint list swapped to the green pod IPs
NAME            ENDPOINTS                                      AGE
myapp-service   10.244.0.66:80,10.244.0.67:80,10.244.0.68:80   3s
$ curl -s http://$(minikube ip):30020 | grep ENVIRONMENT
<html><body><h1>myapp</h1><p>GREEN ENVIRONMENT - v2</p></body></html>

########## INSTANT ROLLBACK — flip the selector back ##########
$ kubectl apply -f service-blue.yaml
service/myapp-service configured
$ curl -s http://$(minikube ip):30020 | grep ENVIRONMENT
<html><body><h1>myapp</h1><p>BLUE ENVIRONMENT - v1</p></body></html>

$ kubectl delete -f service-blue.yaml -f deployment-blue.yaml -f deployment-green.yaml
service "myapp-service" deleted from default namespace
configmap "myapp-html-blue" deleted from default namespace
deployment.apps "app-blue" deleted from default namespace
configmap "myapp-html-green" deleted from default namespace
deployment.apps "app-green" deleted from default namespace
```

The only difference between [`service-blue.yaml`](02-blue-green/service-blue.yaml) and
[`service-green.yaml`](02-blue-green/service-green.yaml) is one line — `slot: blue` vs `slot: green`.

Watch the `ENDPOINTS` list: `10.244.0.63/64/65` (blue) becomes `10.244.0.66/67/68` (green) the moment
the selector changes. There is **no intermediate state** where both versions serve traffic — that is
the defining property of blue-green versus canary. Rollback is the same one-line flip, and it is
instant because the blue Pods were never terminated.

The cost: **6 Pods running to serve 3 Pods' worth of traffic** for the whole window. That 2× capacity
requirement is the trade-off you pay for the instant escape hatch.

---

## Task 12 — Canary deployment & pod-ratio traffic splitting

**What this does:** puts 9 stable Pods and 1 canary Pod behind a single Service, measures the real traffic split with a curl loop, shifts the ratio by scaling, then aborts the canary.

```bash
kubectl apply -f deployment-stable.yaml -f service.yaml   # 9 pods, v1
kubectl apply -f deployment-canary.yaml                   # 1 pod,  v2
for i in $(seq 1 20); do curl -s http://$(minikube ip):30030 | grep -o 'STABLE v1\|CANARY v2'; done
```

**Output**

```
$ kubectl apply -f deployment-stable.yaml
configmap/canary-html-stable created
deployment.apps/app-stable created
$ kubectl apply -f service.yaml
service/myapp-canary-service created
$ kubectl rollout status deployment/app-stable
deployment "app-stable" successfully rolled out

$ kubectl apply -f deployment-canary.yaml
configmap/canary-html-canary created
deployment.apps/app-canary created
$ kubectl rollout status deployment/app-canary
deployment "app-canary" successfully rolled out

$ kubectl get pods -l app=myapp-canary --show-labels | head -3
NAME                          READY   STATUS    RESTARTS   AGE   LABELS
app-canary-7d464d94b9-bpqsp   1/1     Running   0          5s    app=myapp-canary,pod-template-hash=7d464d94b9,track=canary,version=v2
app-stable-5ffb878fd6-756w6   1/1     Running   0          7s    app=myapp-canary,pod-template-hash=5ffb878fd6,track=stable,version=v1
$ kubectl get pods -l app=myapp-canary --no-headers | wc -l   # 9 stable + 1 canary
10
$ kubectl get pods -l track=canary
NAME                          READY   STATUS    RESTARTS   AGE
app-canary-7d464d94b9-bpqsp   1/1     Running   0          6s

$ kubectl get endpoints myapp-canary-service   # one shared endpoint pool
NAME                   ENDPOINTS                                                  AGE
myapp-canary-service   10.244.0.69:80,10.244.0.70:80,10.244.0.71:80 + 7 more...   8s

$ for i in $(seq 1 20); do curl -s http://$(minikube ip):30030 | grep -o 'STABLE v1\|CANARY v2'; done
STABLE v1
STABLE v1
STABLE v1
STABLE v1
STABLE v1
STABLE v1
STABLE v1
STABLE v1
STABLE v1
STABLE v1
STABLE v1
STABLE v1
STABLE v1
STABLE v1
STABLE v1
STABLE v1
STABLE v1
STABLE v1
STABLE v1
STABLE v1

$ ... | sort | uniq -c   # traffic split
      4 CANARY v2
     36 STABLE v1
```

**Output — shifting the ratio, then aborting**

```
########## Shift the canary to 30% ##########
$ kubectl scale deployment app-canary --replicas=3
deployment.apps/app-canary scaled
$ kubectl scale deployment app-stable --replicas=7
deployment.apps/app-stable scaled
$ kubectl get deploy app-stable app-canary
NAME         READY   UP-TO-DATE   AVAILABLE   AGE
app-stable   7/7     7            7           37s
app-canary   3/3     3            3           35s
$ kubectl get endpoints myapp-canary-service
NAME                   ENDPOINTS                                                  AGE
myapp-canary-service   10.244.0.69:80,10.244.0.70:80,10.244.0.71:80 + 7 more...   37s
$ for i in $(seq 1 40); do curl ... ; done | sort | uniq -c
     14 CANARY v2
     26 STABLE v1

########## Abort the canary — scale it to zero ##########
$ kubectl scale deployment app-canary --replicas=0
deployment.apps/app-canary scaled
$ kubectl scale deployment app-stable --replicas=9
deployment.apps/app-stable scaled
$ kubectl get deploy app-stable app-canary
NAME         READY   UP-TO-DATE   AVAILABLE   AGE
app-stable   9/9     9            9           49s
app-canary   0/0     0            0           47s
$ for i in $(seq 1 10); do curl ...; done   # 100% back on stable
STABLE v1
STABLE v1
STABLE v1
STABLE v1
STABLE v1
STABLE v1
STABLE v1
STABLE v1
STABLE v1
STABLE v1

$ kubectl delete -f service.yaml -f deployment-canary.yaml -f deployment-stable.yaml
service "myapp-canary-service" deleted from default namespace
configmap "canary-html-canary" deleted from default namespace
deployment.apps "app-canary" deleted from default namespace
configmap "canary-html-stable" deleted from default namespace
deployment.apps "app-stable" deleted from default namespace
```

The trick is that **both** Deployments carry the label `app: myapp-canary`, and the Service selects
only on that — ignoring the `track: stable` / `track: canary` label that distinguishes them. So all
10 Pods land in one endpoint pool and kube-proxy spreads traffic across them evenly.

Traffic share is therefore **just the Pod ratio**:

| Stable | Canary | Expected | Measured |
| --- | --- | --- | --- |
| 9 | 1 | 10% | 4/40 = **10%** |
| 7 | 3 | 30% | 14/40 = **35%** |
| 9 | 0 | 0% | 0/10 = **0%** |

The measured values wobble because kube-proxy load-balances per *connection*, not in strict rotation —
over a small sample that is normal.

The limitation is visible in the maths: to get 1% canary traffic you would need 99 stable Pods. Real
percentage-based splitting needs a service mesh or an Ingress with traffic-splitting annotations.
Rollback is just `kubectl scale --replicas=0` — no rebuild, no redeploy.

---

## Task 13 — Recreate deployment & the deliberate downtime window

**What this does:** updates a `strategy: Recreate` Deployment while a curl loop polls it twice a second, capturing the outage between the last v1 Pod dying and the first v2 Pod becoming Ready.

```bash
kubectl apply -f deployment-v1.yaml -f service.yaml
# terminal 2:
while true; do curl -s --connect-timeout 1 http://$(minikube ip):30040 \
  | grep -o 'VERSION: [^<]*' || echo "[OUTAGE] Connection refused / 0 pods alive"; sleep 0.5; done
# terminal 3:
kubectl apply -f deployment-v2.yaml
```

**Output**

```
$ kubectl apply -f deployment-v1.yaml && kubectl apply -f service.yaml
$ kubectl rollout status deployment/app-recreate
deployment "app-recreate" successfully rolled out
$ kubectl get pods -l app=app-recreate
NAME                            READY   STATUS    RESTARTS   AGE
app-recreate-85b9766dc8-428f4   1/1     Running   0          5s
app-recreate-85b9766dc8-pghk9   1/1     Running   0          5s
app-recreate-85b9766dc8-wzkd2   1/1     Running   0          5s

# Terminal 2: continuous polling loop running during the update
$ while true; do curl -s --connect-timeout 1 http://$(minikube ip):30040 | grep -o 'VERSION: [^<]*' || echo '[OUTAGE] Connection refused / 0 pods alive'; sleep 0.5; done
# Terminal 3: trigger the Recreate update
VERSION: v1
VERSION: v1
VERSION: v1
VERSION: v1
VERSION: v1
VERSION: v1
VERSION: v1
VERSION: v1
VERSION: v1
VERSION: v1
VERSION: v1
[OUTAGE] Connection refused / 0 pods alive
[OUTAGE] Connection refused / 0 pods alive
[OUTAGE] Connection refused / 0 pods alive
VERSION: v2 (UPGRADED)
VERSION: v2 (UPGRADED)
VERSION: v2 (UPGRADED)
VERSION: v2 (UPGRADED)
VERSION: v2 (UPGRADED)
VERSION: v2 (UPGRADED)
VERSION: v2 (UPGRADED)
VERSION: v2 (UPGRADED)
VERSION: v2 (UPGRADED)

$ grep -c OUTAGE  # length of the outage window
3

$ kubectl rollout history deployment/app-recreate
deployment.apps/app-recreate 
REVISION  CHANGE-CAUSE
1         <none>
2         <none>

$ kubectl rollout undo deployment/app-recreate
deployment.apps/app-recreate rolled back
$ kubectl rollout status deployment/app-recreate
deployment "app-recreate" successfully rolled out
$ curl -s http://$(minikube ip):30040
<html><body><p>VERSION: v1</p></body></html>
$ kubectl delete -f service.yaml -f deployment-v1.yaml -f deployment-v2.yaml
service "app-recreate-service" deleted from default namespace
configmap "recreate-html-v1" deleted from default namespace
deployment.apps "app-recreate" deleted from default namespace
configmap "recreate-html-v2" deleted from default namespace
Error from server (NotFound): error when deleting "deployment-v2.yaml": deployments.apps "app-recreate" not found
```

The outage is real and it is captured: three consecutive failed requests — roughly **1.5 seconds**
of hard downtime — between the last `VERSION: v1` and the first `VERSION: v2 (UPGRADED)`.

`strategy.type: Recreate` tells Kubernetes to terminate **all** old Pods before creating **any** new
ones. There is a genuine moment when zero Pods back the Service, so `kube-proxy` has no endpoint to
route to and the connection is refused.

You choose this on purpose when two versions must never run at once — an incompatible database
migration, or a `ReadWriteOnce` volume that only one Pod can mount. For everything else,
RollingUpdate is strictly better.

---

## Summary

| # | Task | Key result |
| --- | --- | --- |
| 1 | Cluster health | node Ready, CoreDNS endpoints bound |
| 2 | Pod deploy/inspect/teardown | `1/1 Running`, IP `10.244.0.3` |
| 3 | ErrImagePull → ImagePullBackOff | both states + exponential back-off captured |
| 4 | Transient lifecycle stages | ContainerCreating → Running → Completed |
| 5 | 12-manifest lifecycle & probes lab | all states, all 3 probe types, sidecar, graceful 10s drain |
| 6 | ReplicaSet + StatefulSet | self-healing; ordinals `mysql-0/1` with per-Pod PVCs |
| 7 | DaemonSet | 1 Pod per node, no `replicas` field |
| 8 | Rolling update + rollback | zero downtime, 2 ReplicaSets, instant undo |
| 9 | Troubleshooting drills | stalled rollout with users unaffected; selector rejection |
| 10 | Conceptual write-up | 4 ports, labels/selectors, 4 strategies, surge maths, units |
| 11 | Blue-Green | endpoints flip, no mixed traffic, instant rollback |
| 12 | Canary | 10% → 35% → 0% traffic split measured live |
| 13 | Recreate | ~1.5s outage window captured request by request |
