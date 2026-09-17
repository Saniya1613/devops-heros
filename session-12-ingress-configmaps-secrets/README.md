# Session 12 — ConfigMaps, Secrets & Ingress

Configuration decoupling with ConfigMaps, credential isolation with Secrets, and Layer-7 routing with
the NGINX Ingress Controller — path-based, host-based, hybrid, and TLS-terminated.

Cluster: minikube v1.39.0, Kubernetes v1.37.0, ingress-nginx v1.15.1, node IP `192.168.49.2`.
Every command below was actually run; the output is pasted verbatim.

### Contents

| # | Task | Directory |
| --- | --- | --- |
| 1 | Config decoupling via ConfigMaps | `01-configmap/` |
| 2 | ConfigMap live update & pod immobility | `04-full-demo/` |
| 3 | Secrets & base64 mechanics | `02-secret/` |
| 4 | The trailing-newline gotcha | — |
| 5 | Enterprise secret management | — |
| 6 | Combined ConfigMap + Secret injection | `04-full-demo/` |
| 7 | Ingress Resource vs Ingress Controller | — |
| 8 | NGINX Ingress Controller activation | — |
| 9 | Local DNS / `/etc/hosts` mapping | — |
| 10 | L7 path-based routing | `04-full-demo/` |
| 11 | Virtual host-based routing | `03-ingress/` |
| 12 | Hybrid routing architecture | `03-ingress/` |
| 13 | Ingress TLS/HTTPS termination | `03-ingress/` |
| 14 | End-to-end integration & automation | `04-full-demo/` |

---

## Task 1 — Non-sensitive configuration decoupling via ConfigMaps

**What this does:** stores five runtime settings outside the container image and reads individual keys back with JSONPath.

```bash
kubectl apply -f 01-configmap/app-config.yaml
kubectl get configmap yatri-app-config
kubectl describe configmap yatri-app-config
kubectl get configmap yatri-app-config -o jsonpath='{.data.ENVIRONMENT}' && echo ""
```

**Output**

```
$ kubectl apply -f 01-configmap/app-config.yaml
configmap/yatri-app-config created

$ kubectl get configmap yatri-app-config
NAME               DATA   AGE
yatri-app-config   5      0s

$ kubectl describe configmap yatri-app-config
Name:         yatri-app-config
Namespace:    default
Labels:       <none>
Annotations:  <none>

Data
====
DEFAULT_CURRENCY:
----
INR

ENVIRONMENT:
----
production

LOG_LEVEL:
----
INFO

MAX_BOOKING_DAYS:
----
90

PORT:
----
8080


BinaryData
====

Events:  <none>

$ kubectl get configmap yatri-app-config -o jsonpath='{.data.ENVIRONMENT}' && echo ""
production
$ kubectl get configmap yatri-app-config -o jsonpath='{.data.LOG_LEVEL}' && echo ""
INFO
```

`DATA: 5` counts the keys. The point of a ConfigMap is that **the same image ships to dev, staging and
production** — only the ConfigMap differs. Baking `ENVIRONMENT=production` into a Dockerfile means
rebuilding to change a log level.

Note that a ConfigMap is **plain text and not encrypted** — `describe` shows every value. Anything
sensitive belongs in a Secret (Task 3).

---

## Task 2 — ConfigMap live update & pod immobility drill

**What this does:** patches a live ConfigMap and proves that running containers do *not* pick up the change, then forces them to with a rolling restart.

```bash
kubectl patch configmap yatri-app-config --type merge -p '{"data":{"ENVIRONMENT":"staging"}}'
kubectl exec deploy/yatri-backend -- env | grep ENVIRONMENT      # still production!
kubectl rollout restart deployment/yatri-backend
kubectl exec deploy/yatri-backend -- env | grep ENVIRONMENT      # now staging
```

**Output**

```
$ kubectl exec deploy/yatri-backend -- env | grep ENVIRONMENT   # before the patch
ENVIRONMENT=production

$ kubectl patch configmap yatri-app-config --type merge -p '{"data":{"ENVIRONMENT":"staging"}}'
configmap/yatri-app-config patched
$ kubectl get configmap yatri-app-config -o jsonpath='{.data.ENVIRONMENT}'; echo
staging

$ kubectl exec deploy/yatri-backend -- env | grep ENVIRONMENT   # STILL production - env vars are injected once, at container start
ENVIRONMENT=production

$ kubectl rollout restart deployment/yatri-backend
deployment.apps/yatri-backend restarted
$ kubectl rollout status deployment/yatri-backend
deployment "yatri-backend" successfully rolled out

$ kubectl exec deploy/yatri-backend -- env | grep ENVIRONMENT   # new pods picked up staging
ENVIRONMENT=staging

$ kubectl patch configmap yatri-app-config --type merge -p '{"data":{"ENVIRONMENT":"production"}}'   # revert
configmap/yatri-app-config patched
$ kubectl rollout restart deployment/yatri-backend
deployment.apps/yatri-backend restarted
$ kubectl exec deploy/yatri-backend -- env | grep ENVIRONMENT
ENVIRONMENT=production
```

This is the drill's whole lesson. The ConfigMap object updated instantly — `jsonpath` returns
`staging` immediately. But the running container still reports `ENVIRONMENT=production`, because
**environment variables are copied into the process at container start and are immutable for its
lifetime**. No amount of waiting changes that.

`kubectl rollout restart` creates new Pods (rolling, so zero downtime) and those read the current
ConfigMap. The behaviour differs by consumption method:

| How the ConfigMap is consumed | Live update? |
| --- | --- |
| `env` / `envFrom` (environment variables) | **No** — requires a pod restart |
| Mounted as a **volume** | **Yes** — the kubelet refreshes the file within ~60s (but the app must re-read it) |

---

## Task 3 — Sensitive data isolation via Secrets & base64 mechanics

**What this does:** stores database credentials in an Opaque Secret, shows `describe` masking them, then decodes them right back on the CLI.

```bash
kubectl apply -f 02-secret/db-secret.yaml
kubectl describe secret yatri-db-secret
kubectl get secret yatri-db-secret -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 --decode && echo ""
```

**Output**

```
$ kubectl apply -f 02-secret/db-secret.yaml
secret/yatri-db-secret created

$ kubectl get secret yatri-db-secret
NAME              TYPE     DATA   AGE
yatri-db-secret   Opaque   2      0s

$ kubectl describe secret yatri-db-secret   # values masked, only byte lengths shown
Name:         yatri-db-secret
Namespace:    default
Labels:       <none>
Annotations:  <none>

Type:  Opaque

Data
====
POSTGRES_PASSWORD:  14 bytes
POSTGRES_USER:      11 bytes

$ kubectl get secret yatri-db-secret -o jsonpath='{.data.POSTGRES_PASSWORD}'; echo
c2VjcmV0cGFzc3dvcmQ=
$ kubectl get secret yatri-db-secret -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 --decode && echo ""
secretpassword
$ kubectl get secret yatri-db-secret -o jsonpath='{.data.POSTGRES_USER}' | base64 --decode && echo ""
yatri_admin
```

`kubectl describe` shows only `14 bytes` / `11 bytes` — deliberately masked so credentials do not end
up in terminal scrollback or CI logs.

But the very next command decodes `c2VjcmV0cGFzc3dvcmQ=` back to `secretpassword` with no special
privileges. **Base64 is an encoding, not encryption.** Anyone with `get secret` RBAC has the plaintext.

What a Secret actually buys you over a ConfigMap:

- masked from casual `describe` output
- can be encrypted at rest in etcd (`EncryptionConfiguration`)
- RBAC is typically scoped separately and more tightly
- the kubelet mounts them into `tmpfs`, never onto the node's disk
- never sent to a node that has no Pod needing them

---

## Task 4 — The trailing-newline gotcha

**What this does:** shows, byte by byte, how `echo` silently corrupts a base64-encoded password.

```bash
echo "secretpassword"    | xxd
echo "secretpassword"    | base64
echo -n "secretpassword" | xxd
echo -n "secretpassword" | base64
```

**Output**

```
# Broken pattern: echo appends an invisible 0x0a newline byte
$ echo "secretpassword" | xxd
00000000: 7365 6372 6574 7061 7373 776f 7264 0a    secretpassword.
$ echo "secretpassword" | base64
c2VjcmV0cGFzc3dvcmQK

# Correct pattern: echo -n emits the exact byte stream
$ echo -n "secretpassword" | xxd
00000000: 7365 6372 6574 7061 7373 776f 7264       secretpassword
$ echo -n "secretpassword" | base64
c2VjcmV0cGFzc3dvcmQ=

$ echo "Wrong (with newline): $(echo "secretpassword" | base64)"
Wrong (with newline): c2VjcmV0cGFzc3dvcmQK
$ echo "Right (no newline):   $(echo -n "secretpassword" | base64)"
Right (no newline):   c2VjcmV0cGFzc3dvcmQ=

# Decoding the broken value back proves the corruption the database sees:
$ echo 'c2VjcmV0cGFzc3dvcmQK' | base64 -d | xxd
00000000: 7365 6372 6574 7061 7373 776f 7264 0a    secretpassword.
$ echo 'c2VjcmV0cGFzc3dvcmQ=' | base64 -d | xxd
00000000: 7365 6372 6574 7061 7373 776f 7264       secretpassword
```

The hex dump is the proof:

```
echo     →  7365 6372 6574 7061 7373 776f 7264 0a    ← trailing 0a
echo -n  →  7365 6372 6574 7061 7373 776f 7264       ← clean
```

That single `0x0a` byte changes the base64 completely:

| Command | Base64 | Decodes to |
| --- | --- | --- |
| `echo "secretpassword"` | `c2VjcmV0cGFzc3dvcmQ**K**` | `secretpassword\n` ❌ |
| `echo -n "secretpassword"` | `c2VjcmV0cGFzc3dvcmQ**=**` | `secretpassword` ✅ |

**Why it is so painful to debug:** the Pod starts fine, the Secret mounts fine, `kubectl describe`
shows nothing wrong, and the app fails with `password authentication failed`. The password *looks*
identical in every log because the newline is invisible. Postgres receives `secretpassword\n` and
rejects it.

Always use `echo -n`, or better, skip the manual encoding entirely:

```bash
kubectl create secret generic yatri-db-secret \
  --from-literal=POSTGRES_USER=yatri_admin \
  --from-literal=POSTGRES_PASSWORD=secretpassword
```

`--from-literal` encodes the exact bytes and cannot introduce this bug.

---

## Task 5 — Enterprise secret management & pipeline integration

```bash
kubectl get crds | grep -i secret || echo "Standard native secrets in use"
```

**Output**

```
$ kubectl get crds | grep -i secret || echo "Standard native secrets in use"
Standard native secrets in use
```

No external secret CRDs here — this cluster uses native Secrets, which is exactly the setup the rest
of this section argues against for production.

### The vulnerability: committing Secret YAML to Git

[`02-secret/db-secret.yaml`](02-secret/db-secret.yaml) in this repository contains
`c2VjcmV0cGFzc3dvcmQ=`. That is a **real credential in plaintext** for anyone who can read the repo.
It is fine here because it is a throwaway lab value, and it is a serious problem in production:

- **Git history is forever.** Rotating the password does not remove the old one from history; you
  need `git filter-repo` or a BFG rewrite across every clone and fork.
- **Repo RBAC ≠ secret RBAC.** Every contributor, every CI runner, and every forked copy gets it.
- **No rotation, no audit, no expiry.** Nothing records who read it or when.
- Secret scanners flag base64 blobs, but only *after* the push.

### External Secrets Operator (ESO)

The secret never enters Git. A `ExternalSecret` custom resource *references* it, and the operator
syncs the real value from the vendor at runtime:

```
AWS Secrets Manager / Azure Key Vault / HashiCorp Vault
                    │
                    │  (operator authenticates via IRSA / Workload Identity —
                    │   no static credentials anywhere)
                    ▼
        External Secrets Operator  ──watches──► ExternalSecret CR (safe to commit)
                    │
                    ▼
        creates/refreshes a native Kubernetes Secret
                    │
                    ▼
             Pod (env var or mounted volume)
```

Rotating in the vault propagates automatically on the next refresh interval. The alternative,
**HashiCorp Vault Agent Injector**, uses a mutating webhook to add a sidecar that writes secrets
directly into the Pod's `tmpfs` — so no Kubernetes Secret object is created at all.

### CI/CD integration

The same principle applies to the pipeline: the deploy job holds a short-lived token, never the
credential.

```yaml
# GitHub Actions — secrets are injected at runtime, never stored in the repo
jobs:
  deploy:
    permissions:
      id-token: write          # OIDC — no long-lived AWS keys in the repo
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/deploy
      - run: kubectl apply -f k8s/
        env:
          DB_PASSWORD: ${{ secrets.DB_PASSWORD }}   # masked in logs
```

Azure DevOps Variable Groups linked to Key Vault do the same thing. In both cases the manifests in
Git contain a *reference*; the value materialises only inside the running job.

---

## Task 6 — Combined ConfigMap and Secret injection

**What this does:** deploys a backend that pulls bulk config from a ConfigMap with `envFrom` and individual credentials from a Secret with `secretKeyRef`, then verifies both landed.

```bash
kubectl apply -f 04-full-demo/configmap.yaml -f 04-full-demo/secret.yaml -f 04-full-demo/backend.yaml
kubectl exec deploy/yatri-backend -- env | grep -E 'ENVIRONMENT|LOG_LEVEL|POSTGRES|DEFAULT_CURRENCY'
```

**Output**

```
$ kubectl apply -f 04-full-demo/configmap.yaml
configmap/yatri-app-config unchanged
$ kubectl apply -f 04-full-demo/secret.yaml
secret/yatri-db-secret unchanged
$ kubectl apply -f 04-full-demo/backend.yaml
deployment.apps/yatri-backend created
service/yatri-backend-service created
$ kubectl rollout status deployment/yatri-backend
deployment "yatri-backend" successfully rolled out

$ kubectl get pods -l app=yatri-backend
NAME                             READY   STATUS    RESTARTS   AGE
yatri-backend-6b7768749b-k5wr6   1/1     Running   0          7s
yatri-backend-6b7768749b-zgm92   1/1     Running   0          7s

$ kubectl exec deploy/yatri-backend -- env | grep -E 'ENVIRONMENT|LOG_LEVEL|POSTGRES|DEFAULT_CURRENCY|MAX_BOOKING|^PORT'
DEFAULT_CURRENCY=INR
ENVIRONMENT=production
LOG_LEVEL=INFO
MAX_BOOKING_DAYS=90
PORT=8080
POSTGRES_PASSWORD=secretpassword
POSTGRES_USER=yatri_admin
```

All seven variables are present in one environment, from two different sources — see
[`04-full-demo/backend.yaml`](04-full-demo/backend.yaml):

```yaml
envFrom:                          # BULK: every key in the ConfigMap becomes a variable
  - configMapRef:
      name: yatri-app-config

env:                              # GRANULAR: named keys, explicitly mapped
  - name: POSTGRES_PASSWORD
    valueFrom:
      secretKeyRef:
        name: yatri-db-secret
        key: POSTGRES_PASSWORD
```

`envFrom` is convenient but blunt — add a key to the ConfigMap and every Pod gets it on next restart,
and a bad key name can shadow something like `PATH`. `secretKeyRef` is deliberately explicit, which is
what you want for credentials: the manifest documents exactly which secret each Pod can see.

---

## Task 7 — Ingress Resource vs Ingress Controller

```bash
kubectl api-resources | grep -i ingress
```

**Output**

```
$ kubectl api-resources | grep -i ingress
ingressclasses                                   networking.k8s.io/v1              false        IngressClass
ingresses                           ing          networking.k8s.io/v1              true         Ingress
```

The single most common Ingress misunderstanding: **the Ingress resource does nothing on its own.**

| | **Ingress Resource** | **Ingress Controller** |
| --- | --- | --- |
| What it is | A declarative API object (YAML) | A running Pod — a real reverse proxy |
| What it contains | Hostnames, paths, TLS references, backend services | NGINX / Traefik / HAProxy / Envoy + a control loop |
| Where it lives | etcd | A Deployment, usually in its own namespace |
| Does it move traffic? | **No.** It is a routing *specification* | **Yes.** It is the thing packets pass through |
| How many | Many — one per app or team | Usually one (or one per class) per cluster |

`kubectl api-resources` proves the first half: `ingresses` is a **built-in** `networking.k8s.io/v1`
resource, always available. You can `kubectl apply` an Ingress on a cluster with no controller
installed — it will be accepted, stored, and silently ignored forever.

### The controller's control loop

```
   Ingress resources in etcd
            │
            │  (watch)
            ▼
  [ Ingress Controller Pod ]
            │
            ├─ 1. observes Ingress / Service / EndpointSlice objects
            ├─ 2. regenerates nginx.conf from the current rules
            ├─ 3. hot-reloads NGINX
            └─ 4. writes the assigned address back to .status.loadBalancer
                    (this is the ADDRESS column in `kubectl get ingress`)
            │
            ▼
  Real traffic: Client ──► Controller ──► Service ──► Pod
```

`IngressClass` is what binds the two: `spec.ingressClassName: nginx` tells this controller "these
rules are yours". That is how one cluster can run an internal and an external controller side by side.

---

## Task 8 — NGINX Ingress Controller activation & verification

**What this does:** enables the controller on minikube and waits for it to report Ready.

```bash
minikube addons enable ingress
kubectl get pods -n ingress-nginx
kubectl wait --namespace ingress-nginx --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=120s
kubectl get service -n ingress-nginx
kubectl get ingressclass
```

**Output**

```
$ minikube addons enable ingress
* The 'ingress' addon is enabled

$ kubectl get pods -n ingress-nginx
NAME                                       READY   STATUS      RESTARTS   AGE
ingress-nginx-admission-create-7z6kk       0/1     Completed   0          111s
ingress-nginx-admission-patch-phw7n        0/1     Completed   0          110s
ingress-nginx-controller-d7cd8c989-9bq9r   1/1     Running     0          111s

$ kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s
pod/ingress-nginx-controller-d7cd8c989-9bq9r condition met

$ kubectl get service -n ingress-nginx
NAME                                 TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)                      AGE
ingress-nginx-controller             NodePort    10.100.164.68    <none>        80:30589/TCP,443:31220/TCP   112s
ingress-nginx-controller-admission   ClusterIP   10.111.108.198   <none>        443/TCP                      112s

$ kubectl get ingressclass
NAME              CONTROLLER             PARAMETERS   AGE
nginx (default)   k8s.io/ingress-nginx   <none>       111s
```

Three things to read out of this:

- The two `ingress-nginx-admission-*` Jobs show `Completed`, not `Running` — that is correct. They are
  one-shot Jobs that generate and patch the TLS certificate for the **validating admission webhook**,
  which is what rejects a malformed Ingress at `kubectl apply` time rather than at traffic time.
- `ingress-nginx-controller` is a `NodePort` Service on `80:30589, 443:31220`. On a real cloud it would
  be `type: LoadBalancer` — **the one billable load balancer** from Session 11, Task 11.
- `nginx (default)` in the IngressClass output means an Ingress that omits `ingressClassName` is still
  picked up by this controller.

---

## Task 9 — Local DNS resolution & `/etc/hosts` mapping

**What this does:** points the lab hostnames at the cluster IP so host-based routing can be tested without real DNS.

```bash
MINIKUBE_IP=$(minikube ip)
echo "${MINIKUBE_IP}  yatri.local" | sudo tee -a /etc/hosts
grep yatri.local /etc/hosts
getent hosts yatri.local
```

**Output**

```
$ MINIKUBE_IP=$(minikube ip)
$ echo "Minikube IP is: ${MINIKUBE_IP}"
Minikube IP is: 192.168.49.2

$ if ! grep -q "yatri.local" /etc/hosts; then echo "${MINIKUBE_IP}  yatri.local" | sudo tee -a /etc/hosts; fi
192.168.49.2  yatri.local portal.campus.local api.campus.local

$ grep -E 'yatri.local|campus.local' /etc/hosts
192.168.49.2  yatri.local portal.campus.local api.campus.local

$ getent hosts yatri.local
192.168.49.2    yatri.local portal.campus.local api.campus.local
```

`yatri.local` is not a real domain and no DNS server anywhere would resolve it. `/etc/hosts` is
consulted before DNS, so this one line makes the whole Ingress host-routing lab work locally.

This matters because **Ingress routing is driven by the HTTP `Host` header**, not by the IP. The
browser must send `Host: yatri.local` for the controller to match the rule — which is also why
`curl -H "Host: ..."` (Task 11) works without touching `/etc/hosts` at all.

In production this line is replaced by a real DNS A record pointing at the cloud load balancer.

---

## Task 10 — Layer 7 path-based routing

**What this does:** routes `/` to the frontend and `/api/*` to the backend, through a single Ingress on one hostname, with URL rewriting.

```bash
kubectl apply -f 04-full-demo/frontend.yaml -f 04-full-demo/backend.yaml -f 04-full-demo/ingress.yaml
kubectl describe ingress yatri-ingress
curl -s http://yatri.local/     | grep -i "<title>"
curl -s http://yatri.local/api/
```

**Output**

```
$ kubectl apply -f 04-full-demo/frontend.yaml
configmap/yatri-frontend-html created
deployment.apps/yatri-frontend created
service/yatri-frontend-service created
$ kubectl apply -f 04-full-demo/ingress.yaml
ingress.networking.k8s.io/yatri-ingress created

$ kubectl get ingress yatri-ingress
NAME            CLASS   HOSTS         ADDRESS        PORTS   AGE
yatri-ingress   nginx   yatri.local   192.168.49.2   80      12s

$ kubectl describe ingress yatri-ingress
Name:             yatri-ingress
Labels:           app=yatri-app
Namespace:        default
Address:          192.168.49.2
Ingress Class:    nginx
Default backend:  <default>
Rules:
  Host         Path  Backends
  ----         ----  --------
  yatri.local  
               /api(/|$)(.*)   yatri-backend-service:8080 (10.244.0.115:8080,10.244.0.116:8080)
               /()(.*)         yatri-frontend-service:80 (10.244.0.117:80,10.244.0.118:80)
Annotations:   nginx.ingress.kubernetes.io/rewrite-target: /$2
               nginx.ingress.kubernetes.io/use-regex: true
Events:
  Type    Reason  Age               From                      Message
  ----    ------  ----              ----                      -------
  Normal  Sync    2s (x2 over 12s)  nginx-ingress-controller  Scheduled for sync

$ curl -s http://yatri.local/ | grep -i '<title>'
<html><head><title>Welcome to nginx!</title></head>

$ curl -s http://yatri.local/api/
YATRI BACKEND API
ENVIRONMENT: production
LOG_LEVEL: INFO
DEFAULT_CURRENCY: INR
POSTGRES_USER: yatri_admin
POSTGRES_PASSWORD: secretpassword
PATH_REQUESTED: /
```

One hostname, one IP, **two completely different backend services** chosen by URL path. Both backends
are internal `ClusterIP` Services — neither is exposed directly.

The rewrite is the subtle part. See [`04-full-demo/ingress.yaml`](04-full-demo/ingress.yaml):

```yaml
annotations:
  nginx.ingress.kubernetes.io/rewrite-target: /$2
  nginx.ingress.kubernetes.io/use-regex: "true"
paths:
  - path: /api(/|$)(.*)
```

The regex has two capture groups: `(/|$)` is `$1` and `(.*)` is `$2`. `rewrite-target: /$2` forwards
only the second group. So `GET /api/bookings` reaches the backend as `/bookings` — confirmed by the
last line of the output, `PATH_REQUESTED: /` for a request to `/api/`.

Without the rewrite the backend would receive `/api/bookings` and would need to know it sits behind
an Ingress prefix. This keeps the service independent of where it is mounted.

---

## Task 11 — Virtual host-based routing

**What this does:** sends two different hostnames to two different services through the same IP and the same controller.

```bash
curl -s -H "Host: portal.campus.local" http://$(minikube ip)/
curl -skL --resolve portal.campus.local:443:$MK http://portal.campus.local/ | grep -i "<title>"
curl -skL --resolve api.campus.local:443:$MK    http://api.campus.local/api/
```

**Output**

```
$ curl -s -o /dev/null -w '%{http_code}\n' -H "Host: portal.campus.local" http://${MINIKUBE_IP}/
308
# 308 - ingress-nginx force-redirects to HTTPS because this Ingress has a tls: block.

$ curl -skL --resolve portal.campus.local:443:$MK --resolve portal.campus.local:80:$MK http://portal.campus.local/ | grep -i '<title>'
<html><head><title>Welcome to nginx!</title></head>

$ curl -skL --resolve api.campus.local:443:$MK --resolve api.campus.local:80:$MK http://api.campus.local/api/
YATRI BACKEND API
ENVIRONMENT: production
LOG_LEVEL: INFO
DEFAULT_CURRENCY: INR
POSTGRES_USER: yatri_admin
POSTGRES_PASSWORD: secretpassword
PATH_REQUESTED: /

# Same cluster IP, same Ingress controller, two different backend services -
# selected purely by the Host header.
```

`portal.campus.local` returns the frontend's HTML, `api.campus.local` returns the backend's plaintext
— from the **same IP, same port, same controller**. Only the `Host` header differs.

The `308 Permanent Redirect` on plain HTTP is not a fault. Because this Ingress has a `tls:` block,
ingress-nginx applies `ssl-redirect` by default and pushes every HTTP request to HTTPS. Following the
redirect with `-L` lands on the real content. To serve plain HTTP as well you would set
`nginx.ingress.kubernetes.io/ssl-redirect: "false"`.

This is the multi-tenant pattern: 50 subdomains, 50 ClusterIP services, one load balancer.

---

## Task 12 — Hybrid routing architecture

**What this does:** combines host-based and path-based rules in one Ingress resource.

```bash
kubectl apply -f 03-ingress/ingress-tls.yaml
kubectl get ingress campus-ingress-tls
kubectl describe ingress campus-ingress-tls
```

**Output**

```
$ openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt -subj "/CN=campus.local/O=CampusDevOps"
.....+...+...+...+.+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++*...+....+............+..............+.........+.+...+..+....+...........+...+.+......+.........+..+.......+......+..+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++*.+....+......+.....+..........+.....+.......+..+.+......+...+.....+......+.+..................+..+.+............+..+......+..........+.....+.........+...+.............+..+.+.....+.+......+..+..........+..+.........+......+.+.....+.......+......+.....+.+.........+.....+......+...+.......+.....+....+..+....+...+.....+...+...+.+..................+.....+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
....+.....+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++*...+...+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++*.+...+.+...+...........+.......+............+..+.............+.................+.+..+.+.........+..+....+..+..................+......+..........+.....+.+........+.+......+.........+.....+....+.....+.......+...+......+........+..........+......+...........+.+........+.+........+.+.........+..+.+..+......+............+...+.....................+.........+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-----

$ openssl x509 -in tls.crt -noout -subject -dates
subject=CN = campus.local, O = CampusDevOps
notBefore=Sep 17 20:52:53 2026 GMT
notAfter=Sep 17 20:52:53 2027 GMT

$ kubectl create secret tls campus-tls-cert --cert=tls.crt --key=tls.key
secret/campus-tls-cert created
$ kubectl get secret campus-tls-cert
NAME              TYPE                DATA   AGE
campus-tls-cert   kubernetes.io/tls   2      0s

$ kubectl apply -f 03-ingress/ingress-tls.yaml
ingress.networking.k8s.io/campus-ingress-tls created

$ kubectl get ingress campus-ingress-tls
NAME                 CLASS   HOSTS                                  ADDRESS   PORTS     AGE
campus-ingress-tls   nginx   portal.campus.local,api.campus.local             80, 443   12s

$ kubectl describe ingress campus-ingress-tls
Name:             campus-ingress-tls
Labels:           <none>
Namespace:        default
Address:          
Ingress Class:    nginx
Default backend:  <default>
TLS:
  campus-tls-cert terminates portal.campus.local,api.campus.local
Rules:
  Host                 Path  Backends
  ----                 ----  --------
  portal.campus.local  
                       /()(.*)   yatri-frontend-service:80 (10.244.0.117:80,10.244.0.118:80)
  api.campus.local     
                       /api(/|$)(.*)   yatri-backend-service:8080 (10.244.0.115:8080,10.244.0.116:8080)
                       /()(.*)         yatri-backend-service:8080 (10.244.0.115:8080,10.244.0.116:8080)
Annotations:           nginx.ingress.kubernetes.io/rewrite-target: /$2
                       nginx.ingress.kubernetes.io/use-regex: true
Events:
  Type    Reason  Age   From                      Message
  ----    ------  ----  ----                      -------
  Normal  Sync    12s   nginx-ingress-controller  Scheduled for sync
```

The routing table in the `describe` output is the deliverable:

```
  Host                 Path            Backends
  portal.campus.local  /()(.*)         yatri-frontend-service:80   (2 endpoints)
  api.campus.local     /api(/|$)(.*)   yatri-backend-service:8080  (2 endpoints)
                       /()(.*)         yatri-backend-service:8080  (2 endpoints)
```

Host matching happens **first**, then paths are evaluated within the matched host — most specific
first, which is why `/api(/|$)(.*)` is listed above the catch-all `/()(.*)`. Both hostnames share one
`tls:` block and one certificate.

The resolved endpoint IPs beside each backend are a useful sanity check: if that column reads
`<none>`, the Service selector is not matching any Pod and the route will 503 regardless of whether
the Ingress rules are correct.

---

## Task 13 — Ingress TLS/HTTPS termination

**What this does:** generates a self-signed certificate, stores it as a `kubernetes.io/tls` Secret, binds it to the Ingress, and verifies the handshake — including a real failure and its fix.

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt \
  -subj "/CN=campus.local/O=CampusDevOps"
kubectl create secret tls campus-tls-cert --cert=tls.crt --key=tls.key
kubectl apply -f 03-ingress/ingress-tls.yaml
curl -k -v --resolve portal.campus.local:443:$(minikube ip) https://portal.campus.local/
```

**Output**

```
# First attempt - exactly the command from the assignment:
$ openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt \
    -subj "/CN=campus.local/O=CampusDevOps"
$ kubectl create secret tls campus-tls-cert --cert=tls.crt --key=tls.key
secret/campus-tls-cert created

# ...but the controller refused to serve it and fell back to its own fake cert:
$ kubectl logs -n ingress-nginx deploy/ingress-nginx-controller | grep campus-tls-cert
W0917 20:53:38.374846  7 controller.go:1488] SSL certificate "default/campus-tls-cert" does not contain
  a Common Name or Subject Alternative Name for server "portal.campus.local":
  x509: certificate is not valid for any names, but wanted to match portal.campus.local
W0917 20:53:38.375145  7 controller.go:1489] Using default certificate

# Fix: a CN alone is no longer accepted - the cert needs subjectAltName entries.
$ openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt \
    -subj "/CN=campus.local/O=CampusDevOps" \
    -addext "subjectAltName=DNS:campus.local,DNS:portal.campus.local,DNS:api.campus.local"
-----

$ openssl x509 -in tls.crt -noout -subject -ext subjectAltName
subject=CN = campus.local, O = CampusDevOps
X509v3 Subject Alternative Name: 
    DNS:campus.local, DNS:portal.campus.local, DNS:api.campus.local

$ kubectl delete secret campus-tls-cert && kubectl create secret tls campus-tls-cert --cert=tls.crt --key=tls.key
secret/campus-tls-cert created
$ kubectl get secret campus-tls-cert
NAME              TYPE                DATA   AGE
campus-tls-cert   kubernetes.io/tls   2      0s

$ INGRESS_IP=$(minikube ip)
$ curl -k -v --resolve portal.campus.local:443:${INGRESS_IP} https://portal.campus.local/ 2>&1 | grep -E 'Server certificate|subject:|issuer:|SSL connection|HTTP/'
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384 / X25519 / RSASSA-PSS
* Server certificate:
*  subject: CN=campus.local; O=CampusDevOps
*  issuer: CN=campus.local; O=CampusDevOps
< HTTP/2 200 

$ curl -sk --resolve portal.campus.local:443:${INGRESS_IP} https://portal.campus.local/ | grep -i '<title>'
<html><head><title>Welcome to nginx!</title></head>

$ curl -sk --resolve api.campus.local:443:${INGRESS_IP} https://api.campus.local/api/
YATRI BACKEND API
ENVIRONMENT: production
LOG_LEVEL: INFO
DEFAULT_CURRENCY: INR
POSTGRES_USER: yatri_admin
POSTGRES_PASSWORD: secretpassword
PATH_REQUESTED: /
```

### The gotcha worth recording

The assignment's `openssl` command sets only a **Common Name**, and that is no longer enough.
ingress-nginx served its own fallback certificate instead:

```
SSL certificate "default/campus-tls-cert" does not contain a Common Name or Subject
Alternative Name for server "portal.campus.local"
Using default certificate
```

CN-only matching was deprecated by RFC 6125 and dropped from Go's TLS verification in Go 1.15.
Certificates now need **`subjectAltName` entries**, and `CN=campus.local` does not cover the
subdomains `portal.campus.local` and `api.campus.local` anyway. Adding:

```bash
-addext "subjectAltName=DNS:campus.local,DNS:portal.campus.local,DNS:api.campus.local"
```

fixed it — the handshake then presents `subject: CN=campus.local; O=CampusDevOps` and returns
`HTTP/2 200`. If a browser or curl ever shows *"Kubernetes Ingress Controller Fake Certificate"*,
this is almost always why: the controller could not use your cert and quietly fell back.

### What TLS termination means here

The client's TLS session ends **at the Ingress controller**. Traffic from the controller to
`yatri-frontend-service` is plain HTTP inside the cluster network. This is the standard arrangement —
certificates live in one place instead of in every application, and `curl -k` was needed only because
the certificate is self-signed. In production the Secret is populated by cert-manager from Let's
Encrypt, and the Ingress YAML is unchanged.

`-k` is also why the `openssl`-generated key is **not committed** to this repository; see
[`.gitignore`](../.gitignore).

---

## Task 14 — End-to-end integration & automation scripting

**What this does:** runs the whole stack up and back down with two scripts, and confirms nothing is left behind.

```bash
bash 04-full-demo/run-demo.sh
kubectl get configmap,secret,ingress,deploy,svc,pods -l app=yatri-app
bash 04-full-demo/cleanup.sh
```

**Output**

```
$ bash 04-full-demo/run-demo.sh
==> [1/6] Applying ConfigMap (non-sensitive configuration)
configmap/yatri-app-config created
==> [2/6] Applying Secret (sensitive credentials)
secret/yatri-db-secret created
==> [3/6] Deploying backend Deployment + ClusterIP Service
deployment.apps/yatri-backend created
service/yatri-backend-service created
==> [4/6] Deploying frontend Deployment + ClusterIP Service
configmap/yatri-frontend-html created
deployment.apps/yatri-frontend created
service/yatri-frontend-service created
==> [5/6] Applying Ingress (L7 path-based routing)
ingress.networking.k8s.io/yatri-ingress created
==> [6/6] Waiting for rollouts to finish
Waiting for deployment "yatri-backend" rollout to finish: 0 of 2 updated replicas are available...
Waiting for deployment "yatri-backend" rollout to finish: 1 of 2 updated replicas are available...
deployment "yatri-backend" successfully rolled out
Waiting for deployment "yatri-frontend" rollout to finish: 0 of 2 updated replicas are available...
Waiting for deployment "yatri-frontend" rollout to finish: 1 of 2 updated replicas are available...
deployment "yatri-frontend" successfully rolled out

==> Stack is up:
NAME                            DATA   AGE
configmap/yatri-frontend-html   1      1s

NAME                                      CLASS   HOSTS         ADDRESS   PORTS   AGE
ingress.networking.k8s.io/yatri-ingress   nginx   yatri.local             80      1s

NAME                             READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/yatri-backend    2/2     2            2           2s
deployment.apps/yatri-frontend   2/2     2            2           1s

NAME                             TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
service/yatri-backend-service    ClusterIP   10.111.105.144   <none>        8080/TCP   2s
service/yatri-frontend-service   ClusterIP   10.101.163.27    <none>        80/TCP     1s

$ kubectl get configmap,secret,ingress,deploy,svc,pods -l app=yatri-app
NAME                            DATA   AGE
configmap/yatri-frontend-html   1      1s

NAME                                      CLASS   HOSTS         ADDRESS   PORTS   AGE
ingress.networking.k8s.io/yatri-ingress   nginx   yatri.local             80      1s

NAME                             READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/yatri-backend    2/2     2            2           2s
deployment.apps/yatri-frontend   2/2     2            2           1s

NAME                             TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
service/yatri-backend-service    ClusterIP   10.111.105.144   <none>        8080/TCP   2s
service/yatri-frontend-service   ClusterIP   10.101.163.27    <none>        80/TCP     1s

$ bash 04-full-demo/cleanup.sh
==> Deleting Ingress
ingress.networking.k8s.io "yatri-ingress" deleted from default namespace
==> Deleting frontend
configmap "yatri-frontend-html" deleted from default namespace
deployment.apps "yatri-frontend" deleted from default namespace
service "yatri-frontend-service" deleted from default namespace
==> Deleting backend
deployment.apps "yatri-backend" deleted from default namespace
service "yatri-backend-service" deleted from default namespace
==> Deleting Secret
secret "yatri-db-secret" deleted from default namespace
==> Deleting ConfigMap
configmap "yatri-app-config" deleted from default namespace

==> Remaining resources with label app=yatri-app:
No resources found in default namespace.

$ kubectl get ingress yatri-ingress || echo "Ingress deleted"
Ingress deleted
$ kubectl get deployment yatri-backend yatri-frontend || echo "Deployments deleted"
Deployments deleted
```

[`run-demo.sh`](04-full-demo/run-demo.sh) applies the five manifests in dependency order — ConfigMap
and Secret **before** the Deployments that reference them, Ingress last — then blocks on
`kubectl rollout status` so the script fails loudly rather than exiting green on a broken deploy.

[`cleanup.sh`](04-full-demo/cleanup.sh) tears down in **reverse** order with `--ignore-not-found`, so
it is idempotent and safe to run against a partially-deployed stack.

### Multi-document YAML

Both `backend.yaml` and `frontend.yaml` hold several objects in one file, separated by `---`:

```yaml
apiVersion: apps/v1
kind: Deployment
# ...
---
apiVersion: v1
kind: Service
# ...
```

Keeping a Deployment and its Service together means one `kubectl apply` and one `kubectl delete`
handle the unit, and the two can never drift apart in review. `kubectl` applies the documents in
order, which is why the frontend's ConfigMap sits above the Deployment that mounts it.

The label `app: yatri-app` on every object is what makes the single-command audit
(`kubectl get ... -l app=yatri-app`) and the final empty result possible.

---

## Summary

| # | Task | Key result |
| --- | --- | --- |
| 1 | ConfigMap decoupling | 5 keys stored and read back by JSONPath |
| 2 | Live update drill | patched to `staging`, pod still `production` until restart |
| 3 | Secrets & base64 | `describe` masks it; one command decodes it |
| 4 | Trailing-newline gotcha | `0a` byte located in the hex dump |
| 5 | Enterprise secret management | ESO / Vault / CI-CD patterns documented |
| 6 | Combined injection | `envFrom` + `secretKeyRef` merged in one env |
| 7 | Resource vs Controller | built-in API vs the proxy that acts on it |
| 8 | Controller activation | `ingress-nginx-controller` 1/1 Running |
| 9 | `/etc/hosts` mapping | `yatri.local` → `192.168.49.2` |
| 10 | Path-based routing | `/` → frontend, `/api/` → backend, rewrite verified |
| 11 | Host-based routing | two hostnames, one IP, two services |
| 12 | Hybrid routing | full routing table with live endpoints |
| 13 | TLS termination | `HTTP/2 200`; SAN requirement found and fixed |
| 14 | Automation scripts | full up/down cycle, clean teardown |
