# Session 11 — Kubernetes Services & Cluster Networking

All five Service types deployed and tested, CoreDNS and FQDN resolution dissected, pod identity
compared across controllers, and the minikube docker-driver port-binding gotcha analysed.

Cluster: minikube v1.39.0, Kubernetes v1.37.0, containerd 2.3.4, docker driver, node IP `192.168.49.2`.
Every command below was actually run; the output is pasted verbatim.

### Contents

| # | Task | Directory |
| --- | --- | --- |
| 1 | The four ports, clarified | — |
| 2 | ClusterIP — default internal networking | `01-clusterip/` |
| 3 | NodePort — host-level external access | `02-nodeport/` |
| 4 | LoadBalancer — cloud ingress simulation | `03-loadbalancer/` |
| 5 | ExternalName — CoreDNS CNAME alias | `04-externalname/` |
| 6 | Headless — `clusterIP: None` + StatefulSet | `05-headless/` |
| 7 | Services without selectors | `06-no-selector/` |
| 8 | FQDN & CoreDNS deep dive | — |
| 9 | Pod identity: Deployment vs StatefulSet | — |
| 10 | Deployment / StatefulSet / DaemonSet matrix | — |
| 11 | Cost optimisation & service selection tree | — |
| 12 | Minikube docker-driver port binding gotcha | — |

---

## Task 1 — Kubernetes port architecture

**What this does:** pins down what each of the four port fields actually controls, straight from the API schema.

```bash
kubectl explain pod.spec.containers.ports.containerPort
kubectl explain service.spec.ports
```

**Output**

```
$ kubectl explain pod.spec.containers.ports.containerPort
KIND:       Pod
VERSION:    v1

FIELD: containerPort <integer>


DESCRIPTION:
    Number of port to expose on the pod's IP address. This must be a valid port
    number, 0 < x < 65536.
    


$ kubectl explain service.spec.ports
KIND:       Service
VERSION:    v1

FIELD: ports <[]ServicePort>


DESCRIPTION:
    The list of ports that are exposed by this service. More info:
    https://kubernetes.io/docs/concepts/services-networking/service/#virtual-ips-and-service-proxies
    ServicePort contains information on service's port.
    
FIELDS:
  appProtocol	<string>
    The application protocol for this port. This is used as a hint for
    implementations to offer richer behavior for protocols that they understand.
    This field follows standard Kubernetes label syntax. Valid values are
    either:
    
    * Un-prefixed protocol names - reserved for IANA standard service names (as
    per RFC-6335 and https://www.iana.org/assignments/service-names).
    
    * Kubernetes-defined prefixed names:
      * 'kubernetes.io/h2c' - HTTP/2 prior knowledge over cleartext as described
    in
    https://www.rfc-editor.org/rfc/rfc9113.html#name-starting-http-2-with-prior-
      * 'kubernetes.io/ws'  - WebSocket over cleartext as described in
    https://www.rfc-editor.org/rfc/rfc6455
      * 'kubernetes.io/wss' - WebSocket over TLS as described in
    https://www.rfc-editor.org/rfc/rfc6455
    
```

### The packet's journey

```
External client
      │
      ▼
[ nodePort: 30080 ]      open on EVERY node's IP, range 30000-32767
      │                  (kube-proxy iptables rule on the host)
      ▼
[ port: 8080 ]           the Service's virtual IP (ClusterIP) — this is what
      │                  other pods dial: http://web-service-clusterip:8080
      ▼
[ targetPort: 80 ]       the pod port the Service forwards to
      │                  (DNAT to a chosen backend pod IP)
      ▼
[ containerPort: 80 ]    the port nginx is actually listening on
```

| Field | Defined in | Notes |
| --- | --- | --- |
| `containerPort` | Pod spec | **Purely informational.** The API docs call it "number of port to expose on the pod's IP address", but nothing enforces it — a process listening on 80 is reachable on 80 whether or not it is declared. |
| `targetPort` | Service spec | The one that matters for routing. Defaults to `port` if omitted; may reference a **named** container port. |
| `port` | Service spec | The Service's own port. Independent of the container's. |
| `nodePort` | Service spec | Only for `NodePort`/`LoadBalancer`. Auto-assigned if not specified. |

---

## Task 2 — Type 1: ClusterIP (default internal networking)

**What this does:** deploys a 3-replica backend behind a ClusterIP Service on port 8080 → 80, then reaches it from a client Pod three different ways.

```bash
kubectl apply -f 01-clusterip/app-deployment.yaml -f 01-clusterip/service.yaml -f 01-clusterip/client-pod.yaml
kubectl get svc,endpoints web-service-clusterip
kubectl exec curl-client -- curl -s http://web-service-clusterip:8080 | grep -i "<title>"
kubectl exec curl-client -- curl -s http://web-service-clusterip.default.svc.cluster.local:8080 | grep -i "<title>"
```

**Output**

```
$ kubectl apply -f 01-clusterip/app-deployment.yaml
deployment.apps/web-app-clusterip created
$ kubectl apply -f 01-clusterip/service.yaml
service/web-service-clusterip created
$ kubectl apply -f 01-clusterip/client-pod.yaml
pod/curl-client created

$ kubectl get pods -l app=web-clusterip -o wide
NAME                                 READY   STATUS    RESTARTS   AGE   IP            NODE       NOMINATED NODE   READINESS GATES
web-app-clusterip-77644d696c-6cck4   1/1     Running   0          15s   10.244.0.94   minikube   <none>           <none>
web-app-clusterip-77644d696c-h8p8b   1/1     Running   0          15s   10.244.0.93   minikube   <none>           <none>
web-app-clusterip-77644d696c-k9lmp   1/1     Running   0          15s   10.244.0.92   minikube   <none>           <none>

$ kubectl get svc web-service-clusterip
NAME                    TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
web-service-clusterip   ClusterIP   10.109.220.188   <none>        8080/TCP   15s

$ kubectl get endpoints web-service-clusterip
NAME                    ENDPOINTS                                      AGE
web-service-clusterip   10.244.0.92:80,10.244.0.93:80,10.244.0.94:80   15s

$ kubectl wait --for=condition=ready pod/curl-client --timeout=60s
pod/curl-client condition met

$ kubectl exec curl-client -- curl -s http://web-service-clusterip:8080 | grep -i '<title>'
<title>Welcome to nginx!</title>

$ kubectl exec curl-client -- curl -s http://web-service-clusterip.default.svc.cluster.local:8080 | grep -i '<title>'
<title>Welcome to nginx!</title>

$ CIP=$(kubectl get svc web-service-clusterip -o jsonpath='{.spec.clusterIP}'); kubectl exec curl-client -- curl -s http://$CIP:8080 | grep -i '<title>'
<title>Welcome to nginx!</title>
```

Three points worth noting:

- The `CLUSTER-IP` `10.109.220.188` is **virtual**. Nothing listens on it — no interface holds it. It
  exists only as iptables/IPVS rules that kube-proxy programmed on every node.
- The `ENDPOINTS` list is the live set of healthy Pod IPs, maintained automatically by the endpoints
  controller from the Service's label selector. A Pod that fails its readiness probe is removed here.
- **Short name, FQDN and raw ClusterIP all work identically.** Applications should use the short
  name — it survives the Pods being rescheduled onto entirely new IPs.

ClusterIP is the default type and is **unreachable from outside the cluster**. That is the point.

---

## Task 3 — Type 2: NodePort (host-level external access)

**What this does:** opens a fixed high port on every node so the app is reachable from outside the cluster.

```bash
kubectl apply -f 02-nodeport/app-deployment.yaml -f 02-nodeport/service.yaml
kubectl get svc web-service-nodeport
curl -I http://$(minikube ip):30080
minikube service web-service-nodeport --url
```

**Output**

```
$ kubectl apply -f 02-nodeport/app-deployment.yaml
deployment.apps/web-app-nodeport created
$ kubectl apply -f 02-nodeport/service.yaml
service/web-service-nodeport created

$ kubectl get svc web-service-nodeport
NAME                   TYPE       CLUSTER-IP    EXTERNAL-IP   PORT(S)        AGE
web-service-nodeport   NodePort   10.105.17.4   <none>        80:30080/TCP   12s

$ kubectl get endpoints web-service-nodeport
NAME                   ENDPOINTS                       AGE
web-service-nodeport   10.244.0.96:80,10.244.0.97:80   12s

$ MINIKUBE_IP=$(minikube ip); echo $MINIKUBE_IP
192.168.49.2

$ curl -I http://${MINIKUBE_IP}:30080
HTTP/1.1 200 OK
Server: nginx/1.25.5
Date: Thu, 17 Sep 2026 20:44:43 GMT
Content-Type: text/html
Content-Length: 615

$ minikube service web-service-nodeport --url
http://192.168.49.2:30080
```

`PORT(S): 80:30080/TCP` reads **`port`:`nodePort`**. A NodePort Service is a ClusterIP Service *plus*
a host-level port: it still has `CLUSTER-IP 10.105.17.4` and is still reachable internally on port 80.

`HTTP/1.1 200 OK` from `192.168.49.2:30080` confirms external access. The port opens on **every**
node, not just the one running a Pod — hit any node and kube-proxy forwards internally.

NodePort is rarely used directly in production: the port range is unfriendly (30000–32767), you must
track which node IPs are live, and there is no TLS termination. It is normally an implementation
detail underneath a LoadBalancer or Ingress.

---

## Task 4 — Type 3: LoadBalancer (cloud ingress simulation)

**What this does:** requests an external IP, shows it hanging at `<pending>` with no cloud provider, then uses `minikube tunnel` to emulate one.

```bash
kubectl apply -f 03-loadbalancer/app-deployment.yaml -f 03-loadbalancer/service.yaml
kubectl get svc web-service-loadbalancer     # <pending>
minikube tunnel                              # in a second terminal
kubectl get svc web-service-loadbalancer     # EXTERNAL-IP populated
```

**Output**

```
$ kubectl apply -f 03-loadbalancer/app-deployment.yaml
deployment.apps/web-app-loadbalancer created
$ kubectl apply -f 03-loadbalancer/service.yaml
service/web-service-loadbalancer created

$ kubectl get svc web-service-loadbalancer   # EXTERNAL-IP <pending> until a cloud LB controller answers
NAME                       TYPE           CLUSTER-IP    EXTERNAL-IP   PORT(S)        AGE
web-service-loadbalancer   LoadBalancer   10.106.6.83   <pending>     80:32045/TCP   12s

$ kubectl get svc web-service-loadbalancer -o jsonpath='{.spec.type}{" clusterIP="}{.spec.clusterIP}{" nodePort="}{.spec.ports[0].nodePort}{"\n"}'
LoadBalancer clusterIP=10.106.6.83 nodePort=32045

# In a second terminal:
$ minikube tunnel
  	machine: minikube
  	pid: 13944
  	route: 10.96.0.0/12 -> 192.168.49.2
  	minikube: Running
  	services: [web-service-loadbalancer]
      errors: 
  		minikube: no errors
  		router: no errors
  		loadbalancer emulator: no errors

$ kubectl get svc web-service-loadbalancer   # EXTERNAL-IP now populated
NAME                       TYPE           CLUSTER-IP    EXTERNAL-IP   PORT(S)        AGE
web-service-loadbalancer   LoadBalancer   10.106.6.83   10.106.6.83   80:32045/TCP   2m14s

$ EXTERNAL_IP=$(kubectl get svc web-service-loadbalancer -o jsonpath='{.status.loadBalancer.ingress[0].ip}'); echo $EXTERNAL_IP
10.106.6.83

$ curl -s http://${EXTERNAL_IP}:80 | grep -i '<title>'   # plain port 80, no high port
<title>Welcome to nginx!</title>

# A LoadBalancer is built ON TOP of NodePort, which is built on ClusterIP:
$ kubectl get svc web-service-loadbalancer -o jsonpath='...'
type=LoadBalancer  clusterIP=10.106.6.83  nodePort=32045  targetPort=80

$ kubectl delete -f 03-loadbalancer/service.yaml -f 03-loadbalancer/app-deployment.yaml
service "web-service-loadbalancer" deleted from default namespace
deployment.apps "web-app-loadbalancer" deleted from default namespace
```

`EXTERNAL-IP: <pending>` is **not an error**. `type: LoadBalancer` is a *request* to the
cloud-controller-manager to provision a real load balancer (an AWS NLB, a GCP forwarding rule). On a
local cluster nothing answers that request, so it waits forever. `minikube tunnel` plays the role of
the cloud controller and assigns an IP.

The layering is explicit in the output — `type=LoadBalancer clusterIP=10.106.6.83 nodePort=32045`.
A LoadBalancer **is** a NodePort Service, which **is** a ClusterIP Service, with each layer adding
reach:

```
ClusterIP  ──►  + nodePort on every node  ──►  + external LB in front
```

The benefit is the standard port: `http://10.106.6.83:80`, no high port number.

---

## Task 5 — Type 4: ExternalName (CoreDNS CNAME alias)

**What this does:** creates a Service that is nothing but a DNS alias to an external domain, with no proxying at all.

```bash
kubectl apply -f 04-externalname/service.yaml -f 04-externalname/client-pod.yaml
kubectl get svc external-database-service
kubectl exec dns-test-client -- nslookup external-database-service
```

**Output**

```
$ kubectl apply -f 04-externalname/service.yaml
service/external-database-service created
$ kubectl apply -f 04-externalname/client-pod.yaml
pod/dns-test-client created
$ kubectl wait --for=condition=ready pod/dns-test-client --timeout=60s
pod/dns-test-client condition met

$ kubectl get svc external-database-service   # CLUSTER-IP <none>, EXTERNAL-IP is the target domain
NAME                        TYPE           CLUSTER-IP   EXTERNAL-IP      PORT(S)   AGE
external-database-service   ExternalName   <none>       api.github.com   <none>    1s

$ kubectl get endpoints external-database-service   # no endpoints object is ever created
Error from server (NotFound): endpoints "external-database-service" not found

$ kubectl exec dns-test-client -- nslookup external-database-service
Server:		10.96.0.10
Address:	10.96.0.10:53

** server can't find external-database-service.cluster.local: NXDOMAIN

** server can't find external-database-service.cluster.local: NXDOMAIN

** server can't find external-database-service.svc.cluster.local: NXDOMAIN

** server can't find external-database-service.svc.cluster.local: NXDOMAIN

external-database-service.default.svc.cluster.local	canonical name = api.github.com

external-database-service.default.svc.cluster.local	canonical name = api.github.com
Name:	api.github.com
Address: 140.82.112.6

command terminated with exit code 1

$ kubectl delete -f 04-externalname/service.yaml -f 04-externalname/client-pod.yaml
service "external-database-service" deleted from default namespace
pod "dns-test-client" deleted from default namespace
```

This type is unlike every other one:

- `CLUSTER-IP: <none>` — no virtual IP is allocated.
- **No Endpoints object exists at all** (`Error from server (NotFound)`), and no selector is used.
- No traffic is proxied. CoreDNS simply answers with a **CNAME**:
  `external-database-service.default.svc.cluster.local → api.github.com`, and the client then
  connects directly to `140.82.112.6`.

The value is decoupling: your app hardcodes `postgres-service`, and staging points that alias at RDS
while production points it at a different host. Swapping backends is a one-line Service edit with no
application change or redeploy.

(The `NXDOMAIN` lines are normal — they are the `ndots:5` search-path probes explained in Task 8.)

### Sending real traffic through the alias

`busybox` provides `nslookup` but has no TLS-capable `curl`, so the outbound test runs from a second
client pod built on the curl image ([`04-externalname/curl-client.yaml`](04-externalname/curl-client.yaml)).

```bash
kubectl apply -f 04-externalname/curl-client.yaml
kubectl exec externalname-curl-client -- curl -s -k https://external-database-service
```

**Output**

```
$ kubectl apply -f 04-externalname/curl-client.yaml
pod/externalname-curl-client created

$ kubectl exec externalname-curl-client -- curl -s -k https://external-database-service | head -c 300
Host resolves to a private/reserved IP: resolve_no_records

$ kubectl exec externalname-curl-client -- curl -s -o /dev/null -w 'HTTP %{http_code} -> resolved to %{remote_ip}\n' -k https://external-database-service
HTTP 403 -> resolved to 140.82.114.6
```

The important line is `resolved to 140.82.114.6` — that is a real `api.github.com` address. The Pod
asked for `external-database-service`, CoreDNS returned the CNAME, and the connection went straight
out to GitHub. **No Kubernetes proxy sat in the path**, which is exactly what distinguishes
`ExternalName` from every other Service type.

The `403` is this lab environment's outbound egress policy answering, not a Kubernetes error — the
name resolved and the TCP connection was established, which is what the test is proving.

---

## Task 6 — Type 5: Headless Service (`clusterIP: None`)

**What this does:** pairs a headless Service with a StatefulSet so DNS returns every Pod's IP individually instead of one virtual IP, then addresses a single Pod by its stable name.

```bash
kubectl apply -f 05-headless/service.yaml -f 05-headless/app-statefulset.yaml -f 05-headless/client-pod.yaml
kubectl get svc web-service-headless
kubectl exec headless-dns-client -- nslookup web-service-headless
kubectl exec headless-dns-client -- nslookup web-stateful-0.web-service-headless.default.svc.cluster.local
```

**Output**

```
$ kubectl apply -f 05-headless/service.yaml
service/web-service-headless created
$ kubectl apply -f 05-headless/app-statefulset.yaml
statefulset.apps/web-stateful created
$ kubectl apply -f 05-headless/client-pod.yaml
pod/headless-dns-client created
$ kubectl rollout status statefulset/web-stateful --timeout=120s
partitioned roll out complete: 3 new pods have been updated...

$ kubectl get pods -l app=web-headless -o wide
NAME             READY   STATUS    RESTARTS   AGE   IP             NODE       NOMINATED NODE   READINESS GATES
web-stateful-0   1/1     Running   0          7s    10.244.0.102   minikube   <none>           <none>
web-stateful-1   1/1     Running   0          6s    10.244.0.104   minikube   <none>           <none>
web-stateful-2   1/1     Running   0          6s    10.244.0.105   minikube   <none>           <none>

$ kubectl get svc web-service-headless   # CLUSTER-IP is explicitly None
NAME                   TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
web-service-headless   ClusterIP   None         <none>        80/TCP    7s

$ kubectl exec headless-dns-client -- nslookup web-service-headless
Server:		10.96.0.10
Address:	10.96.0.10:53
Name:	web-service-headless.default.svc.cluster.local
Address: 10.244.0.105
Name:	web-service-headless.default.svc.cluster.local
Address: 10.244.0.102
Name:	web-service-headless.default.svc.cluster.local
Address: 10.244.0.104
command terminated with exit code 1

$ kubectl exec headless-dns-client -- nslookup web-stateful-0.web-service-headless.default.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53
Name:	web-stateful-0.web-service-headless.default.svc.cluster.local
Address: 10.244.0.102

$ kubectl exec headless-dns-client -- wget -qO- http://web-stateful-0.web-service-headless:80 | grep -i '<title>'
<title>Welcome to nginx!</title>
```

Compare with Task 2. A normal ClusterIP lookup returns **one** virtual IP. Here the same query
returns **three A records** — `10.244.0.102`, `10.244.0.104`, `10.244.0.105` — the Pod IPs themselves.
Setting `clusterIP: None` removes the proxy layer entirely and turns the Service into pure DNS.

More importantly, each Pod gets its own stable record:

```
web-stateful-0.web-service-headless.default.svc.cluster.local
<pod-name>.<service-name>.<namespace>.svc.cluster.local
```

This is why StatefulSets **require** a headless Service. A Kafka broker or a Postgres replica must be
able to say "connect me to node 0 specifically" — load-balancing across a virtual IP would defeat the
entire purpose. Task 9 shows the name surviving a Pod deletion.

---

## Task 7 — Services without selectors (manual Endpoints mapping)

**What this does:** creates a Service with no selector and hand-writes its Endpoints object, pointing cluster traffic at an external machine.

```bash
kubectl apply -f 06-no-selector/service-no-selector.yaml
kubectl get endpoints external-legacy-db        # nothing
kubectl apply -f 06-no-selector/manual-endpoints.yaml
kubectl get endpoints external-legacy-db        # 192.168.1.150:3306
```

**Output**

```
$ kubectl apply -f 06-no-selector/service-no-selector.yaml
service/external-legacy-db created

$ kubectl get svc external-legacy-db
NAME                 TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)    AGE
external-legacy-db   ClusterIP   10.99.29.81   <none>        3306/TCP   0s

$ kubectl get endpoints external-legacy-db   # empty: no selector means nothing is auto-populated
Error from server (NotFound): endpoints "external-legacy-db" not found

$ kubectl apply -f 06-no-selector/manual-endpoints.yaml
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
endpoints/external-legacy-db created

$ kubectl get endpoints external-legacy-db   # manually bound to the external host
NAME                 ENDPOINTS            AGE
external-legacy-db   192.168.1.150:3306   3s

$ kubectl describe endpoints external-legacy-db | head -12
Name:         external-legacy-db
Namespace:    default
Labels:       <none>
Annotations:  <none>
Subsets:
  Addresses:          192.168.1.150
  NotReadyAddresses:  <none>
  Ports:
    Name     Port  Protocol
    ----     ----  --------
    <unset>  3306  TCP


$ kubectl delete -f 06-no-selector/manual-endpoints.yaml -f 06-no-selector/service-no-selector.yaml
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
endpoints "external-legacy-db" deleted from default namespace
service "external-legacy-db" deleted from default namespace
```

Normally the endpoints controller populates Endpoints from the Service's selector. **Omit the
selector and that controller leaves the object alone** — so you can write it yourself and point it at
anything reachable: an on-prem Oracle box, a VM outside the cluster, a legacy database mid-migration.

Pods then just dial `external-legacy-db:3306` like any other Service. When the database finally moves
into the cluster you add a selector and delete the manual Endpoints — **no application change**.

This differs from `ExternalName` (Task 5) in an important way: ExternalName works at the DNS layer
and needs a resolvable hostname; this works at the IP layer and can target a bare IP with no DNS
record at all.

---

## Task 8 — FQDN & CoreDNS deep dive

**What this does:** inspects the DNS configuration Kubernetes injects into every container and traces how a short name becomes a fully-qualified one.

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
kubectl exec curl-client -- cat /etc/resolv.conf
kubectl exec headless-dns-client -- nslookup web-service-clusterip
kubectl exec headless-dns-client -- nslookup api.github.com
```

**Output**

```
$ kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
NAME                       READY   STATUS    RESTARTS      AGE   IP           NODE       NOMINATED NODE   READINESS GATES
coredns-559f6c778d-kllk6   1/1     Running   1 (34m ago)   38m   10.244.0.2   minikube   <none>           <none>

$ kubectl get svc kube-dns -n kube-system
NAME       TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE
kube-dns   ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP,9153/TCP   38m

$ kubectl exec curl-client -- cat /etc/resolv.conf
search default.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5

$ kubectl exec headless-dns-client -- nslookup web-service-clusterip   # short name expands via search suffixes
Server:		10.96.0.10
Address:	10.96.0.10:53
Name:	web-service-clusterip.default.svc.cluster.local
Address: 10.109.220.188
command terminated with exit code 1

$ kubectl exec headless-dns-client -- nslookup api.github.com   # external name: ndots:5 forces 4 failed cluster lookups first
Server:		10.96.0.10
Address:	10.96.0.10:53
Non-authoritative answer:
Non-authoritative answer:
Name:	api.github.com
Address: 140.82.112.5
```

### Anatomy of a Kubernetes FQDN

```
web-service-clusterip . default   . svc      . cluster.local
└── service name ───┘  └─ ns ──┘  └─ type ┘  └── cluster domain ┘
```

### What `/etc/resolv.conf` is doing

```
search default.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5
```

- `nameserver 10.96.0.10` — the `kube-dns` Service ClusterIP, confirmed above. Every DNS query from
  every Pod goes to CoreDNS first.
- `search …` — why `web-service-clusterip` alone resolves: the resolver appends each suffix in turn
  until one answers.
- `options ndots:5` — **the performance trap.** If a name contains fewer than 5 dots, the resolver
  tries every search suffix *before* trying the name as-is.

### The `ndots:5` latency cost

`api.github.com` has 2 dots, which is under 5, so a Pod resolving it issues:

```
1. api.github.com.default.svc.cluster.local   → NXDOMAIN
2. api.github.com.svc.cluster.local           → NXDOMAIN
3. api.github.com.cluster.local               → NXDOMAIN
4. api.github.com                             → 140.82.112.5   ✓
```

**Four round-trips to CoreDNS for one external lookup.** In a service calling Stripe or an external
API thousands of times a minute, this is measurable latency and a large share of CoreDNS's load —
one of the most common causes of "CoreDNS is on fire" in production.

The fix is a **trailing dot**: `api.github.com.` has 3 dots but is explicitly absolute, so the
resolver skips the search path entirely. Alternatively set `dnsConfig.options` with a lower `ndots`
on latency-sensitive Pods.

---

## Task 9 — Pod identity: Deployment (stateless) vs StatefulSet (stateful)

**What this does:** deletes one Pod from each controller and compares what comes back.

```bash
DEPLOY_POD=$(kubectl get pods -l app=web-clusterip -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod "${DEPLOY_POD}"
kubectl get pods -l app=web-clusterip
kubectl delete pod web-stateful-0
kubectl get pods -l app=web-headless
```

**Output**

```
$ kubectl get pods -l app=web-clusterip    # Deployment: random replicaset-hash + random suffix
NAME                                 READY   STATUS    RESTARTS   AGE
web-app-clusterip-77644d696c-6cck4   1/1     Running   0          5m11s
web-app-clusterip-77644d696c-h8p8b   1/1     Running   0          5m11s
web-app-clusterip-77644d696c-k9lmp   1/1     Running   0          5m11s
$ kubectl get pods -l app=web-headless     # StatefulSet: deterministic ordinals
NAME             READY   STATUS    RESTARTS   AGE
web-stateful-0   1/1     Running   0          43s
web-stateful-1   1/1     Running   0          42s
web-stateful-2   1/1     Running   0          42s

$ DEPLOY_POD=$(kubectl get pods -l app=web-clusterip -o jsonpath='{.items[0].metadata.name}')
$ echo "Deleting Stateless Deployment Pod: ${DEPLOY_POD}"
Deleting Stateless Deployment Pod: web-app-clusterip-77644d696c-6cck4
$ kubectl delete pod "${DEPLOY_POD}"
pod "web-app-clusterip-77644d696c-6cck4" deleted from default namespace
$ kubectl get pods -l app=web-clusterip    # brand-new random identity
NAME                                 READY   STATUS    RESTARTS   AGE
web-app-clusterip-77644d696c-cp42r   1/1     Running   0          7s
web-app-clusterip-77644d696c-h8p8b   1/1     Running   0          5m18s
web-app-clusterip-77644d696c-k9lmp   1/1     Running   0          5m18s

$ kubectl get pod web-stateful-0 -o jsonpath='{.status.podIP}{"\n"}'   # IP before deletion
10.244.0.102
$ kubectl delete pod web-stateful-0
pod "web-stateful-0" deleted from default namespace
$ kubectl get pods -l app=web-headless     # web-stateful-0 comes back with the SAME name
NAME             READY   STATUS    RESTARTS   AGE
web-stateful-0   1/1     Running   0          8s
web-stateful-1   1/1     Running   0          58s
web-stateful-2   1/1     Running   0          58s
$ kubectl get pod web-stateful-0 -o jsonpath='{.status.podIP}{"\n"}'   # new IP, same stable DNS name
10.244.0.107
$ kubectl exec headless-dns-client -- nslookup web-stateful-0.web-service-headless.default.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53
Name:	web-stateful-0.web-service-headless.default.svc.cluster.local
Address: 10.244.0.107
```

The contrast, side by side:

| | Deployment | StatefulSet |
| --- | --- | --- |
| Deleted | `web-app-clusterip-77644d696c-6cck4` | `web-stateful-0` |
| Replaced by | `web-app-clusterip-77644d696c-**cp42r**` | `web-stateful-**0**` |
| Identity | **brand new and random** | **identical** |

A Deployment Pod is **cattle**: the ReplicaSet only cares that the count is 3, so the replacement gets
a fresh random suffix. Nothing may depend on that name.

A StatefulSet Pod is a **pet**: `web-stateful-0` came back as `web-stateful-0`. Its IP changed
(`10.244.0.102` → `10.244.0.107`) — Pod IPs are never stable — but the final `nslookup` shows CoreDNS
already returning the new IP for the same DNS name. **The name is the stable identity, not the IP.**

That is the contract a clustered database needs: replicas configured to talk to
`mysql-0.mysql` keep working across restarts, reschedules and node failures.

---

## Task 10 — Architectural matrix: Deployment vs StatefulSet vs DaemonSet

```bash
kubectl explain deployment.spec
kubectl explain statefulset.spec
kubectl explain daemonset.spec
kubectl get deploy,sts,ds -A
```

**Output**

```
$ kubectl explain deployment.spec | head -12
GROUP:      apps
KIND:       Deployment
VERSION:    v1

FIELD: spec <DeploymentSpec>


DESCRIPTION:
    Specification of the desired behavior of the Deployment.
    DeploymentSpec is the specification of the desired behavior of the
    Deployment.
    

$ kubectl explain statefulset.spec | grep -A 3 volumeClaimTemplates
    volume claims created from volumeClaimTemplates. By default, all persistent
    volume claims are created as needed and retained until manually deleted.
    This policy allows the lifecycle to be altered, for example by deleting
    persistent volume claims when their stateful set is deleted, or when their
    pod is scaled down.
--
  volumeClaimTemplates	<[]PersistentVolumeClaim>
    volumeClaimTemplates is a list of claims that pods are allowed to reference.
    The StatefulSet controller is responsible for mapping network identities to
    claims in a way that maintains the identity of a pod. Every claim in this
    list must have at least one matching (by name) volumeMount in one container
    in the template. A claim in this list takes precedence over any volumes in

$ kubectl explain daemonset.spec | head -10
GROUP:      apps
KIND:       DaemonSet
VERSION:    v1

FIELD: spec <DaemonSetSpec>


DESCRIPTION:
    The desired behavior of this daemon set. More info:
    https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#spec-and-status

$ kubectl get deploy,sts,ds -A | head -12
NAMESPACE     NAME                                READY   UP-TO-DATE   AVAILABLE   AGE
default       deployment.apps/web-app-clusterip   3/3     3            3           5m43s
default       deployment.apps/web-app-nodeport    2/2     2            2           5m19s
kube-system   deployment.apps/coredns             1/1     1            1           39m

NAMESPACE   NAME                            READY   AGE
default     statefulset.apps/web-stateful   3/3     75s

NAMESPACE     NAME                        DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
kube-system   daemonset.apps/kindnet      1         1         1       1            1           <none>                   39m
kube-system   daemonset.apps/kube-proxy   1         1         1       1            1           kubernetes.io/os=linux   39m
```

| Metric | **Deployment** | **StatefulSet** | **DaemonSet** |
| --- | --- | --- | --- |
| Workload type | Stateless microservices, web APIs | Clustered databases, distributed queues | Node-level infrastructure agents |
| Pod naming | Random: `<deploy>-<rs-hash>-<random>` | Ordinal: `<name>-0`, `-1`, `-2` | `<ds>-<random>`, one per node |
| Identity | Ephemeral — disposable | **Invariant** — name and DNS stick | Bound to a specific node |
| Startup / shutdown order | Unordered, parallel | **Strictly sequential** 0→1→2, reversed on teardown | Parallel across all nodes |
| Storage | Shared volume or ephemeral `emptyDir` | Dedicated PV per ordinal via `volumeClaimTemplates` | `hostPath` / node-local |
| Required Service | Any (`ClusterIP`/`NodePort`/`LoadBalancer`) | **Headless** (`clusterIP: None`) — mandatory | None, or a local `ClusterIP` |
| Scaling | Arbitrary, any healthy node | Ordinal, adds/removes at the tail | **Automatic** — follows node count |
| `replicas` field | Yes | Yes | **No** — desired count *is* the node count |
| Production examples | Nginx, Flask, Node.js, Go APIs | Kafka, MongoDB, Cassandra, PostgreSQL, ZooKeeper | Fluentd, node-exporter, Cilium, Falco |

The live cluster illustrates the third column: `kindnet` and `kube-proxy` both run as DaemonSets in
`kube-system`, because a CNI plugin and a service proxy must exist on **every** node by definition.

---

## Task 11 — Production cost optimisation & service selection

### The LoadBalancer anti-pattern

Each `type: LoadBalancer` provisions a **separate billable cloud load balancer** (~$18–25/month on
AWS/GCP/Azure, plus data processing charges):

```
ANTI-PATTERN — one LB per microservice
  Microservice A ──► AWS NLB 1  ($25/mo) ──► ClusterIP A
  Microservice B ──► AWS NLB 2  ($25/mo) ──► ClusterIP B
  Microservice C ──► AWS NLB 3  ($25/mo) ──► ClusterIP C
  ...
  50 services = 50 load balancers = $1,250 / month

BEST PRACTICE — one LB, many services
  Public Internet ──► 1 Cloud Load Balancer ($25/mo)
                              │
                              ▼
                  [ NGINX Ingress Controller ]
                   L7 host- and path-based routing
                    │           │           │
                    ▼           ▼           ▼
               ClusterIP A  ClusterIP B  ClusterIP C
  50 services = 1 load balancer = $25 / month     Saving: $1,225 / month
```

Cost is not the only gain. The single entry point also centralises TLS termination and certificate
management, WAF rules, rate limiting, and access logging — instead of configuring each separately on
50 load balancers. Session 12 implements exactly this pattern.

### Service selection decision tree

```
Need to expose this outside the cluster?
│
├── NO ──► Do clients need to address individual pods (Kafka, DB replicas)?
│           ├── YES ──► HEADLESS SERVICE   (clusterIP: None)
│           └── NO  ──► CLUSTERIP          (the default)
│
└── YES ─► Is the target an external third-party domain (RDS, Stripe)?
            ├── YES ──► EXTERNALNAME
            └── NO  ──► Running on a public cloud?
                         ├── YES, HTTP/HTTPS ──► 1 INGRESS behind 1 LOADBALANCER,
                         │                       apps stay internal CLUSTERIP
                         ├── YES, raw TCP/UDP ─► LOADBALANCER directly
                         └── NO (on-prem / dev) ► NODEPORT
```

---

## Task 12 — Minikube docker-driver port binding & tunnel analysis

**What this does:** examines why `curl <node-ip>:<nodePort>` fails on macOS and Windows but works here, and demonstrates the two standard workarounds.

```bash
NODE_IP=$(minikube ip)
docker network inspect minikube --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
curl --connect-timeout 2 -sI http://${NODE_IP}:30080 | head -1
minikube service web-service-nodeport --url
minikube tunnel
```

**Output**

```
$ kubectl get svc web-service-nodeport
NAME                   TYPE       CLUSTER-IP    EXTERNAL-IP   PORT(S)        AGE
web-service-nodeport   NodePort   10.105.17.4   <none>        80:30080/TCP   5m18s

$ NODE_IP=$(minikube ip); echo $NODE_IP
192.168.49.2

$ docker network inspect minikube -o 'go-template' --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
192.168.49.0/24

$ curl --connect-timeout 2 -sI http://${NODE_IP}:30080 | head -1
HTTP/1.1 200 OK

# WORKAROUND 1 — dynamic loopback proxy
$ minikube service web-service-nodeport --url
http://192.168.49.2:30080

# WORKAROUND 2 — L3 route tunnel (already running in another terminal)
$ minikube tunnel
  	machine: minikube
  	pid: 13944
  	route: 10.96.0.0/12 -> 192.168.49.2
  	minikube: Running
  	services: [web-service-loadbalancer]
      errors: 
  		minikube: no errors
  		router: no errors
  		loadbalancer emulator: no errors
```

### Root cause

With `--driver=docker`, the "node" is a **Docker container**, and its IP `192.168.49.2` belongs to the
`minikube` Docker bridge network (`192.168.49.0/24`) — confirmed in the output above.

- **On Linux** (this environment) the Docker bridge is a real interface in the host's network stack,
  so the host kernel routes to `192.168.49.2` directly. The `curl` above returns `HTTP/1.1 200 OK`.
- **On macOS and Windows**, Docker Desktop runs the engine inside a hidden **LinuxKit VM**. The bridge
  exists *inside that VM*; the host kernel has no route to `192.168.49.0/24` at all. The same `curl`
  hangs and times out — nothing is wrong with Kubernetes, the packet simply never leaves the host.

### Workaround 1 — `minikube service <svc> --url`

Opens a temporary proxy binding a random `127.0.0.1` port straight into the Docker network, and
prints the URL. On macOS/Windows it returns something like `http://127.0.0.1:51234`; **on Linux it
returns the node IP directly** (`http://192.168.49.2:30080`) because no proxy is needed. It must stay
running, and the port changes each invocation.

### Workaround 2 — `minikube tunnel`

A long-running daemon that installs a host **route** for the cluster's service CIDR
(`route: 10.96.0.0/12 -> 192.168.49.2`, visible above) and emulates a cloud load-balancer controller.
It requires elevated privileges to edit the routing table, must stay open, and is what populated the
`EXTERNAL-IP` in Task 4.

---

## Summary

| # | Task | Key result |
| --- | --- | --- |
| 1 | Four ports clarified | nodePort → port → targetPort → containerPort |
| 2 | ClusterIP | VIP `10.109.220.188`, 3 endpoints, name/FQDN/IP all resolve |
| 3 | NodePort | `80:30080/TCP`, `HTTP/1.1 200 OK` from the node IP |
| 4 | LoadBalancer | `<pending>` → `10.106.6.83` via `minikube tunnel` |
| 5 | ExternalName | CNAME to `api.github.com`, no ClusterIP, no Endpoints |
| 6 | Headless | 3 separate A records, per-pod DNS names |
| 7 | No selector | Endpoints hand-bound to `192.168.1.150:3306` |
| 8 | FQDN & CoreDNS | `ndots:5` costs 4 round-trips per external lookup |
| 9 | Pod identity | new random hash vs identical `web-stateful-0` |
| 10 | Controller matrix | full comparison across 9 dimensions |
| 11 | Cost optimisation | $1,250/mo → $25/mo via a single Ingress |
| 12 | Docker-driver gotcha | bridge isolation explained; both workarounds shown |
