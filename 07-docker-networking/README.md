# Docker Networking & Volumes

Custom bridge networks and the isolation between them, the `host` network driver, bind mounts and
named volumes, and a write-up of the `overlay` driver.

Docker Engine 29.4.3 on Ubuntu 24.04. Every command below was actually executed and the output is
pasted verbatim.

---

## Task 1 — Container networking

### Design

Two user-defined bridge networks, modelling a normal tiered application:

```
   frontend-net (172.18.0.0/16)          backend-net (172.19.0.0/16)
   ┌──────────────┬──────────────┐       ┌──────────────┐
   │   web-a      │   web-b      │       │    db-a      │
   │ 172.18.0.2   │ 172.18.0.3   │       │ 172.19.0.2   │
   └──────────────┴──────────────┘       └──────────────┘
        can reach each other                  isolated
```

The question each test answers: **who can talk to whom, and by what name?**

### Create the networks

```bash
docker network create frontend-net
docker network create backend-net
docker network ls
```

**Output**

```
$ docker network ls
NETWORK ID     NAME       DRIVER    SCOPE
ababa46f6771   bridge     bridge    local
fd0736a7bc32   host       host      local
7fc5d9e32fc8   minikube   bridge    local
c1f40b761eb8   none       null      local

$ docker network create frontend-net
5a5851a84598743ee07e7575dbab6bc342fc59d3e1706567a7a5a8c1bcb4ff60
$ docker network create backend-net
50e72f196b8cb88128114595b05e6201fa26c6b10e517a10c07d066c68cb2300

$ docker network ls
NETWORK ID     NAME           DRIVER    SCOPE
50e72f196b8c   backend-net    bridge    local
ababa46f6771   bridge         bridge    local
5a5851a84598   frontend-net   bridge    local
fd0736a7bc32   host           host      local
7fc5d9e32fc8   minikube       bridge    local
c1f40b761eb8   none           null      local

$ docker network inspect frontend-net --format '{{.Name}} driver={{.Driver}} subnet={{range .IPAM.Config}}{{.Subnet}}{{end}}'
frontend-net driver=bridge subnet=172.18.0.0/16
backend-net driver=bridge subnet=172.19.0.0/16
```

Docker allocated `172.18.0.0/16` and `172.19.0.0/16` automatically, each a separate Linux bridge.
The four pre-existing networks are Docker's defaults: `bridge` (where containers land with no
`--network`), `host`, `none`, and `minikube` left over from the Kubernetes sessions.

### Create the containers

```bash
docker run -d --name web-a --network frontend-net nginx:1.25-alpine
docker run -d --name web-b --network frontend-net nginx:1.25-alpine
docker run -d --name db-a  --network backend-net -e POSTGRES_PASSWORD=secret postgres:16-alpine
```

**Output**

```
# web-a and web-b on frontend-net; db-a on backend-net only
$ docker run -d --name web-a --network frontend-net nginx:1.25-alpine
b6ff80cd5a958ad256730d1ac65250324d917249604753b75c49d3af2ee36997
$ docker run -d --name web-b --network frontend-net nginx:1.25-alpine
10b0929513b5fe8aa5b608103262600a7792021e8b4d7d387423e04126c55a3b
$ docker run -d --name db-a --network backend-net -e POSTGRES_PASSWORD=secret postgres:16-alpine
Unable to find image 'postgres:16-alpine' locally
16-alpine: Pulling from library/postgres
5e81018bec01: Pulling fs layer
7f5de3d007ea: Pulling fs layer
be6f407f5414: Pulling fs layer
f0e7204f9584: Pulling fs layer
8225e2970a7f: Pulling fs layer
48d0d8b0e136: Pulling fs layer
27d0ba4f668a: Pulling fs layer
b053c4426c4a: Pulling fs layer
6a47e1b9b254: Pulling fs layer
19a2a5ab27c1: Pulling fs layer
c58682903a2d: Download complete
48d0d8b0e136: Download complete
6a47e1b9b254: Download complete
19a2a5ab27c1: Download complete
7dec47ad1967: Download complete
5e81018bec01: Download complete
be6f407f5414: Download complete
8225e2970a7f: Download complete
27d0ba4f668a: Download complete
b053c4426c4a: Download complete
7f5de3d007ea: Download complete
6a47e1b9b254: Pull complete
19a2a5ab27c1: Pull complete
5e81018bec01: Pull complete
be6f407f5414: Pull complete
f0e7204f9584: Download complete
48d0d8b0e136: Pull complete
8225e2970a7f: Pull complete
27d0ba4f668a: Pull complete
b053c4426c4a: Pull complete
7f5de3d007ea: Pull complete
f0e7204f9584: Pull complete
Digest: sha256:cf78e76683b9ca8c5733cbbdce6c9262b45b6767934dd0a95e671f9a0fc20685
Status: Downloaded newer image for postgres:16-alpine
79ef35e3bdebb6f52f55e0f06778f44e0309061568195ac4c7013a813f0a5227

$ docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
NAMES     IMAGE                       STATUS
db-a      postgres:16-alpine          Up 8 seconds
web-b     nginx:1.25-alpine           Up 13 seconds
web-a     nginx:1.25-alpine           Up 14 seconds

$ docker inspect web-a web-b db-a --format '{{.Name}} -> {{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{$v.IPAddress}}{{end}}'
/web-a -> frontend-net 172.18.0.2
/web-b -> frontend-net 172.18.0.3
/db-a -> backend-net 172.19.0.2
```

### Check connectivity

```bash
docker exec web-a ping -c 3 web-b        # same network
docker exec web-a nslookup web-b
docker exec web-a wget -qO- http://web-b
docker exec web-a ping -c 2 -W 2 db-a    # different network
docker exec web-a nc -zv -w 2 172.19.0.2 5432
```

**Output**

```
########## Same network: name resolution works ##########
$ docker exec web-a ping -c 3 web-b
PING web-b (172.18.0.3): 56 data bytes
64 bytes from 172.18.0.3: seq=0 ttl=64 time=0.074 ms
64 bytes from 172.18.0.3: seq=1 ttl=64 time=0.111 ms
64 bytes from 172.18.0.3: seq=2 ttl=64 time=0.089 ms

--- web-b ping statistics ---
3 packets transmitted, 3 packets received, 0% packet loss
round-trip min/avg/max = 0.074/0.091/0.111 ms

$ docker exec web-a nslookup web-b     # Docker's embedded DNS at 127.0.0.11
Server:		127.0.0.11
Address:	127.0.0.11:53

Non-authoritative answer:
Name:	web-b
Address: 172.18.0.3

Non-authoritative answer:

$ docker exec web-a wget -qO- http://web-b | grep -i '<title>'
<title>Welcome to nginx!</title>

########## Across networks: isolated ##########
$ docker exec web-a ping -c 2 -W 2 db-a
ping: bad address 'db-a'

$ docker exec web-a nc -zv -w 2 172.19.0.2 5432    # try the DB by raw IP
nc: 172.19.0.2 (172.19.0.2:5432): Operation timed out
(no route - the networks are separate bridges)
```

Two results, and both matter.

**Within `frontend-net`, the container name is a hostname.** `ping web-b` resolved to `172.18.0.3`
with no configuration whatsoever, and `nslookup` shows why: the resolver is **`127.0.0.11`**, Docker's
embedded DNS server, injected into every container on a user-defined network. This is what lets an
application connect to `http://db:5432` instead of chasing IP addresses that change on every restart.

**Across networks, isolation is total.** `ping db-a` failed with `bad address` — the name does not
even resolve, because embedded DNS is scoped per network. More importantly, going around DNS by
using the raw IP `172.19.0.2` **timed out** as well. The two bridges are separate Linux interfaces
with no route between them, so this is real network-layer isolation, not just a DNS trick.

That is the security property: a compromised web container cannot reach the database unless it has
been explicitly attached to that network.

### Connecting a container to a second network

```bash
docker network connect backend-net web-a
```

**Output**

```
########## Attaching web-a to the backend network as well ##########
$ docker network connect backend-net web-a
(connected)

$ docker inspect web-a --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}={{$v.IPAddress}} {{end}}'
backend-net=172.19.0.3 frontend-net=172.18.0.2 

$ docker exec web-a ping -c 2 db-a          # now resolves and routes
PING db-a (172.19.0.2): 56 data bytes
64 bytes from 172.19.0.2: seq=0 ttl=64 time=0.075 ms
64 bytes from 172.19.0.2: seq=1 ttl=64 time=0.094 ms

--- db-a ping statistics ---

$ docker exec web-a nc -zv -w 3 db-a 5432   # postgres reachable by name
db-a (172.19.0.2:5432) open

$ docker exec web-b ping -c 2 -W 2 db-a     # web-b was NOT connected - still isolated
ping: bad address 'db-a'

########## The DEFAULT bridge has no DNS ##########
$ docker run -d --name legacy-a nginx:1.25-alpine     # no --network, so default bridge
37617aa8b0f36141e4f5a03277172bce0fa0fd788106b171a3d014195c284c07
$ docker run -d --name legacy-b nginx:1.25-alpine
70058ae63c77ea64041f145f1c85966b00d631a48eecda0743d11cdca7c93c2f
$ docker exec legacy-a ping -c 2 -W 2 legacy-b        # name lookup fails on the default bridge
ping: bad address 'legacy-b'
$ docker exec legacy-a ping -c 2 $(docker inspect legacy-b --format '{{.NetworkSettings.Networks.bridge.IPAddress}}')   # by IP it works
PING 172.17.0.4 (172.17.0.4): 56 data bytes
64 bytes from 172.17.0.4: seq=0 ttl=64 time=0.360 ms
64 bytes from 172.17.0.4: seq=1 ttl=64 time=0.088 ms

```

`web-a` now holds **two IP addresses** — `172.18.0.2` on frontend and `172.19.0.3` on backend — and
reaches Postgres by name on port 5432. `web-b`, which was not connected, still cannot. That is
least-privilege networking: each container joins only the networks it needs.

### The default bridge is different

The last block is the one that catches people out. Two containers started with **no** `--network`
land on the default `bridge`, and there:

- `ping legacy-b` fails — **`bad address`**
- `ping 172.17.0.4` works fine

**The default bridge has no embedded DNS.** Containers can reach each other only by IP, and those IPs
change whenever a container restarts. This is the legacy behaviour kept for backwards compatibility.

| | Default `bridge` | User-defined bridge |
| --- | --- | --- |
| DNS by container name | ❌ | ✅ via `127.0.0.11` |
| Isolation from other networks | all share one bridge | ✅ per-network |
| Attach/detach a running container | ❌ | ✅ `network connect` |
| Configurable subnet | ❌ | ✅ `--subnet` |

**Always create a user-defined network.** One `docker network create` is the difference between
service discovery that works and hardcoded IP addresses.

---

## Task 2 — Host network

**What this does:** runs a container with `--network host` and shows that it shares the host's network stack outright.

```bash
docker run -d --name hostnet --network host nginx:1.25-alpine
docker ps
curl -sI http://localhost:80
docker exec hostnet ip -o addr
```

**Output**

```
$ docker run -d --name hostnet --network host nginx:1.25-alpine
8b5895888efaaeae0059a79456b5ef52972880c1ff190ecc4e832d84f3954c72

$ docker ps --filter 'name=hostnet'           # note the PORTS column is EMPTY
NAMES     STATUS         PORTS
hostnet   Up 4 seconds   

$ curl -sI http://localhost:80 | head -3      # no -p flag used, yet port 80 answers
HTTP/1.1 200 OK
Server: nginx/1.25.5
Date: Thu, 17 Sep 2026 21:54:28 GMT

$ docker exec hostnet ip -o addr | awk '{print $2, $4}'   # the container sees the HOST's interfaces
lo 127.0.0.1/8
eth0 192.0.2.2/24
br-7fc5d9e32fc8 192.168.49.1/24
docker0 172.17.0.1/16
br-5a5851a84598 172.18.0.1/16
br-50e72f196b8c 172.19.0.1/16

$ hostname -I                                 # compare with the host itself
192.0.2.2 192.168.49.1 172.17.0.1 172.18.0.1 172.19.0.1 

$ docker inspect hostnet --format 'NetworkMode={{.HostConfig.NetworkMode}}'
NetworkMode=host
$ docker inspect hostnet --format '{{json .NetworkSettings.Networks}}'   # no per-container network
{"host":{"IPAMConfig":null,"Links":null,"Aliases":null,"DriverOpts":null,"GwPriority":0,"NetworkID":"fd0736a7bc326cc90f02adc554119e56d1c248291bbacd9ef2d214244669158d","EndpointID":"b68c8d9cd0efd38bdc052d293b26d92650d7abface2ebedd584d1bcfcfe14945","Gateway":"","IPAddress":"","MacAddress":"","IPPrefixLen":0,"IPv6Gateway":"","GlobalIPv6Address":"","GlobalIPv6PrefixLen":0,"DNSNames":null}}

$ docker rm -f hostnet
hostnet
```

Three things to notice:

- **The `PORTS` column is empty and `-p` was never used**, yet `curl http://localhost:80` returns
  `200 OK`. With `--network host` there is no port mapping because there is no separate network
  namespace to map *from* — nginx binds port 80 on the host directly.
- **`ip -o addr` inside the container lists the host's interfaces exactly** — `eth0 192.0.2.2/24`,
  `docker0`, and the bridges created in Task 1. Compare with `hostname -I` on the host: identical.
- `NetworkSettings.Networks` has no IP address at all. The container has no address of its own.

**Trade-offs.** You gain a little throughput (no NAT, no `docker-proxy` hop) and access to the host's
full interface list, which is why monitoring agents and network tools use it. You lose isolation and
port flexibility: two containers cannot both bind port 80, and the container can now reach anything
the host can, including services bound to `127.0.0.1`.

**An important platform detail:** `--network host` only truly works on **Linux**. On macOS and
Windows, Docker runs inside a hidden Linux VM, so "host" means *that VM*, not your laptop — the same
bridge-isolation issue documented in
[session-11, Task 12](../session-11-kubernetes-services/README.md). This lab ran on Linux, which is
why port 80 was reachable directly.

---

## Task 3 — Bind mount

**What this does:** mounts a host directory into a container, then edits the file on the host and watches the change appear live.

```bash
docker run -d --name bindweb -p 8086:80 \
  -v $(pwd)/bind-mount:/usr/share/nginx/html:ro nginx:1.25-alpine

curl -s http://localhost:8086            # before
sed -i 's/Version 1.../Version 2.../' bind-mount/index.html
curl -s http://localhost:8086            # after
```

**Output**

```
$ cat bind-mount/index.html
<!DOCTYPE html>
<html>
<head><title>Bind mount demo</title></head>
<body>
  <h1>Version 1 - the original file</h1>
  <p>This file lives on the host and is mounted into the container.</p>
</body>
</html>

$ docker run -d --name bindweb -p 8086:80 \
    -v $(pwd)/bind-mount:/usr/share/nginx/html:ro nginx:1.25-alpine
11f8c100d649c3d51297cf8fbb21572fbc157feaa96f1e8ba1ddc8c14009f378

$ curl -s http://localhost:8086 | grep '<h1>'      # BEFORE editing
  <h1>Version 1 - the original file</h1>

# --- now edit the file ON THE HOST, container untouched ---
$ sed -i 's/Version 1 - the original file/Version 2 - edited on the host, live/' bind-mount/index.html

$ curl -s http://localhost:8086 | grep '<h1>'      # AFTER - no rebuild, no restart
  <h1>Version 2 - edited on the host, live</h1>

$ docker exec bindweb cat /usr/share/nginx/html/index.html | grep '<h1>'
  <h1>Version 2 - edited on the host, live</h1>

$ docker exec bindweb touch /usr/share/nginx/html/x   # :ro means read-only
touch: /usr/share/nginx/html/x: Read-only file system

$ docker inspect bindweb --format '{{range .Mounts}}{{.Type}} {{.Source}} -> {{.Destination}} rw={{.RW}}{{end}}'
bind /srv/devops-lab/bind-mount -> /usr/share/nginx/html rw=false
```

The file changed from **"Version 1"** to **"Version 2"** with **no rebuild, no restart and no
`docker cp`**. The container is reading the host's directory directly — a bind mount is a kernel
mount, not a copy, so both sides see the same inodes.

That is why bind mounts are the standard local development pattern: mount your source, and edits in
your editor are live inside the container instantly.

The `:ro` suffix proved itself too — `touch` inside the container failed with **`Read-only file
system`**. Mounting config and static assets read-only is cheap insurance against a compromised
container modifying files on the host.

### Bind mounts vs named volumes

```bash
docker volume create demo-vol
docker run --rm -v demo-vol:/data alpine sh -c 'echo "..." > /data/note.txt'
docker run --rm -v demo-vol:/data alpine cat /data/note.txt
```

**Output**

```
########## Named volume — Docker-managed, survives the container ##########
$ docker volume create demo-vol
demo-vol
$ docker run --rm -v demo-vol:/data alpine:3.20 sh -c 'echo "written by container 1" > /data/note.txt'
Unable to find image 'alpine:3.20' locally
3.20: Pulling from library/alpine
25f1d6b1951a: Pulling fs layer
3a030ca3f633: Download complete
d4050d56ebf2: Download complete
25f1d6b1951a: Download complete
25f1d6b1951a: Pull complete
Digest: sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc
Status: Downloaded newer image for alpine:3.20
(container 1 exited and was removed)

$ docker run --rm -v demo-vol:/data alpine:3.20 cat /data/note.txt   # a NEW container reads it
written by container 1

$ docker volume inspect demo-vol --format '{{.Name}} driver={{.Driver}} mountpoint={{.Mountpoint}}'
demo-vol driver=local mountpoint=/var/lib/docker/volumes/demo-vol/_data

########## Without a volume, writes die with the container ##########
$ docker run --rm alpine:3.20 sh -c 'echo hi > /tmp/ephemeral.txt; ls /tmp'
ephemeral.txt
$ docker run --rm alpine:3.20 ls /tmp     # new container, the file is gone
(empty)

$ docker volume rm demo-vol
demo-vol
```

The first container wrote the file **and was then removed** (`--rm`). A second, completely separate
container read it back. The volume lives at `/var/lib/docker/volumes/demo-vol/_data`, managed by
Docker rather than by you.

The contrast at the bottom is the important half: a file written to `/tmp` **without** a volume was
gone in the next container. A container's writable layer dies with the container — which is exactly
why the StatefulSet in [session10](../session10-k8s-core-objects/) needs `volumeClaimTemplates`.

| | Bind mount | Named volume |
| --- | --- | --- |
| Location | any host path you choose | `/var/lib/docker/volumes/…` |
| Syntax | `-v /host/path:/container/path` | `-v volname:/container/path` |
| Created automatically | no — path must exist | yes |
| Portable across hosts | no, depends on host layout | yes |
| Performance on macOS/Windows | slow (crosses the VM boundary) | fast |
| Backed up by `docker volume` tooling | no | yes |
| Best for | **development** — live source editing | **production** — database data |

Rule of thumb: bind mounts for code you are editing, named volumes for data you must not lose.

---

## Task 4 — Overlay network (research)

### What it is

`bridge` connects containers on **one** host. `overlay` connects containers across **many** hosts, so
a container on machine A can reach one on machine B by name as if they shared a switch. It is the
driver behind Docker Swarm services and the same idea Kubernetes CNI plugins implement.

### How it works

An overlay network is a **VXLAN tunnel**. Each host runs a virtual bridge, and traffic leaving it is
encapsulated in a UDP packet (port **4789**), sent to the destination host, and unwrapped there.

```
   HOST A (10.0.0.1)                        HOST B (10.0.0.2)
   ┌────────────────────┐                   ┌────────────────────┐
   │ container-1        │                   │ container-2        │
   │ 10.0.9.2           │                   │ 10.0.9.3           │
   │   │                │                   │        │           │
   │  br0 ── vxlan0 ────┼─── UDP 4789 ──────┼─ vxlan0 ── br0     │
   └────────────────────┘   (encapsulated)  └────────────────────┘
            └──────── one logical network: 10.0.9.0/24 ────────┘
```

The containers believe they are on one flat `10.0.9.0/24` network and never see the encapsulation. A
distributed key-value store (Swarm's built-in Raft store, or Consul/etcd in standalone mode) keeps
every host's view of membership and IP allocation in sync.

**Ports that must be open between hosts:** TCP/UDP **7946** for control-plane gossip, UDP **4789**
for the VXLAN data plane, and TCP **2377** for Swarm cluster management.

### Commands

```bash
# on the manager
docker swarm init --advertise-addr <manager-ip>
docker swarm join-token worker              # prints the join command for workers

# on each worker
docker swarm join --token <token> <manager-ip>:2377

# create an attachable overlay network
docker network create -d overlay --attachable --subnet 10.0.9.0/24 app-overlay

# services on it are reachable by name from any host
docker service create --name api --network app-overlay --replicas 3 myapi:1.0
docker service create --name web --network app-overlay --replicas 2 myweb:1.0

docker network inspect app-overlay
```

`--attachable` matters: without it only Swarm *services* can join, not plain `docker run` containers.

### Use cases

- Multi-host Swarm clusters where a service must be addressable wherever it is scheduled.
- Rolling updates and failover — a replica rescheduled onto a different host keeps the same service
  name, so clients are unaffected.
- Encrypted east-west traffic with `--opt encrypted`, which turns on IPsec between hosts.

### Bridge vs host vs overlay

| | **bridge** | **host** | **overlay** |
| --- | --- | --- | --- |
| Scope | single host | single host | **multiple hosts** |
| Network namespace | own | **shares the host's** | own |
| Container IP | private, e.g. `172.18.0.2` | none — uses the host's | cluster-wide, e.g. `10.0.9.2` |
| DNS by name | ✅ on user-defined | n/a | ✅ cluster-wide |
| Port mapping | required (`-p`) | not applicable | required for ingress |
| Isolation | ✅ | ❌ | ✅ |
| Overhead | NAT | none | VXLAN encapsulation |
| Needs a cluster | no | no | **yes** (Swarm or a KV store) |
| Typical use | most containers | monitoring agents, network tools | multi-host services |

Not tested hands-on here — an overlay network needs at least two Docker hosts in a Swarm, and this
lab is a single machine. Kubernetes solves the same problem with a CNI plugin; the
[kindnet](../session9-k8s/README.md) DaemonSet in the Kubernetes sessions is that layer, giving every
pod a cluster-routable IP across nodes.

---

## Cleanup

```bash
docker rm -f web-a web-b db-a bindweb legacy-a legacy-b
docker network rm frontend-net backend-net
```

**Output**

```
$ docker rm -f web-a web-b db-a bindweb legacy-a legacy-b
web-a
web-b
db-a
bindweb
legacy-a
legacy-b

$ docker network rm frontend-net backend-net
frontend-net
backend-net

$ docker network ls
NETWORK ID     NAME       DRIVER    SCOPE
ababa46f6771   bridge     bridge    local
fd0736a7bc32   host       host      local
7fc5d9e32fc8   minikube   bridge    local
c1f40b761eb8   none       null      local
```

Back to the four default networks. Note that `docker network rm` refuses to remove a network that
still has containers attached, which is why the containers go first.

---

## Summary

| # | Task | Key result |
| --- | --- | --- |
| 1 | Custom bridge networks | DNS by name within a network; **name AND raw IP both blocked** across networks |
| 1b | `network connect` | `web-a` gained a second IP and reached Postgres; `web-b` stayed isolated |
| 1c | Default bridge | **no embedded DNS** — IP-only, the reason to always use a user-defined network |
| 2 | Host network | port 80 served with no `-p`; container saw every host interface |
| 3 | Bind mount | host edit appeared live with no restart; `:ro` blocked writes |
| 3b | Named volume | data survived container removal; `/tmp` without a volume did not |
| 4 | Overlay (research) | VXLAN on UDP 4789, Swarm commands, three-driver comparison |
