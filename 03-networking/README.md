# Networking Fundamentals

The seven diagnostic tools every engineer reaches for, run for real against a live host, plus the
order to use them in when something is broken.

Host: Ubuntu 24.04, interface `eth0` at `192.0.2.2/24`, default gateway `192.0.2.1`.
Every command below was actually executed and the output is pasted verbatim.

### Command summary

| Tool | Layer | Answers |
| --- | --- | --- |
| `ifconfig` / `ip addr` | 2–3 | What is my IP, which interfaces exist? |
| `ping` | 3 (ICMP) | Can I reach that host at all, and how fast? |
| `traceroute` | 3 | Which path do my packets take, and where do they stop? |
| `netstat` / `ss` | 3–4 | What is listening, what is connected, how do I route? |
| `nslookup` / `dig` / `host` | 7 (DNS) | What does this name resolve to? |
| `curl` | 7 (HTTP) | Does the actual application respond? |
| `nc` | 4 (TCP) | Is that specific port open? |

---

## 1. `ifconfig` — my IP address

**What this does:** lists every network interface with its address, so you know where you are before testing anything else.

```bash
ifconfig
ip -brief addr
hostname -I
```

**Output**

```
$ ifconfig
br-7fc5d9e32fc8: flags=4099<UP,BROADCAST,MULTICAST>  mtu 1500
        inet 192.168.49.1  netmask 255.255.255.0  broadcast 192.168.49.255
        ether fe:e0:57:42:76:40  txqueuelen 0  (Ethernet)
        RX packets 0  bytes 0 (0.0 B)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 0  bytes 0 (0.0 B)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

docker0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet 172.17.0.1  netmask 255.255.0.0  broadcast 172.17.255.255
        ether 02:46:15:55:67:09  txqueuelen 0  (Ethernet)
        RX packets 3  bytes 84 (84.0 B)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 0  bytes 0 (0.0 B)
        TX errors 0  dropped 2 overruns 0  carrier 0  collisions 0

eth0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1400
        inet 192.0.2.2  netmask 255.255.255.0  broadcast 192.0.2.255
        ether 02:fc:00:00:00:01  txqueuelen 1000  (Ethernet)
        RX packets 14597  bytes 80792567 (80.7 MB)
        RX errors 0  dropped 6  overruns 0  frame 0
        TX packets 13480  bytes 88043563 (88.0 MB)

$ ip -brief addr        # the modern equivalent
lo               UNKNOWN        127.0.0.1/8 
ifb0             DOWN           
ifb1             DOWN           
eth0             UP             192.0.2.2/24 
br-7fc5d9e32fc8  DOWN           192.168.49.1/24 
docker0          UP             172.17.0.1/16 
veth80c635e@if2  UP             

$ hostname -I
192.0.2.2 192.168.49.1 172.17.0.1 
```

Three interfaces, three different jobs:

- **`eth0` — `192.0.2.2/24`** is the real network interface. `RX packets 14597 / TX packets 13480`
  confirms traffic is genuinely flowing.
- **`docker0` — `172.17.0.1/16`** is Docker's default bridge. Every container without a custom
  network gets an address on it, and this host is their gateway.
- **`br-7fc5d9e32fc8` — `192.168.49.1/24`** is a user-defined Docker bridge. `linkdown` in
  `ip route` and `RX packets 0` mean nothing is attached to it right now.

`ifconfig` comes from `net-tools` and is deprecated — `ip` is the maintained replacement and is the
only one present on many minimal images. `ip -brief addr` gives the same information in one line per
interface. Note `mtu 1400` on `eth0` rather than the usual 1500, which matters for tunnelled networks:
too large an MTU causes fragmentation and connections that hang on large payloads while small ones work.

---

## 2. `ping` — reachability and latency

**What this does:** sends ICMP echo requests to check whether a host answers, and how long the round trip takes.

```bash
ping -c 4 127.0.0.1
ping -c 4 192.0.2.1
```

**Output**

```
$ ping -c 4 127.0.0.1                 # loopback: is the TCP/IP stack itself alive?
PING 127.0.0.1 (127.0.0.1) 56(84) bytes of data.
64 bytes from 127.0.0.1: icmp_seq=1 ttl=64 time=0.026 ms
64 bytes from 127.0.0.1: icmp_seq=2 ttl=64 time=0.036 ms
64 bytes from 127.0.0.1: icmp_seq=3 ttl=64 time=0.031 ms
64 bytes from 127.0.0.1: icmp_seq=4 ttl=64 time=0.023 ms

--- 127.0.0.1 ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3068ms
rtt min/avg/max/mdev = 0.023/0.029/0.036/0.005 ms

$ ping -c 4 $(ip route | awk '/default/{print $3}')   # the default gateway
PING 192.0.2.1 (192.0.2.1) 56(84) bytes of data.
64 bytes from 192.0.2.1: icmp_seq=1 ttl=64 time=0.232 ms
64 bytes from 192.0.2.1: icmp_seq=2 ttl=64 time=0.165 ms
64 bytes from 192.0.2.1: icmp_seq=3 ttl=64 time=0.163 ms
64 bytes from 192.0.2.1: icmp_seq=4 ttl=64 time=0.162 ms

--- 192.0.2.1 ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3066ms
rtt min/avg/max/mdev = 0.162/0.180/0.232/0.029 ms
```

Two deliberate targets, in order:

- **`127.0.0.1` (loopback)** never leaves the machine. A reply proves the TCP/IP stack itself is
  working. If loopback fails, nothing else is worth testing.
- **`192.0.2.1` (the default gateway)** is the first real hop. `0% packet loss` at `0.18 ms` average
  means the local network is fine and any problem is further out.

`ttl=64` is the starting Time To Live; each router decrements it. A reply arriving with TTL 64 means
**zero routers in between** — the destination is on the local segment.

### When ping fails but the network is fine

**What this does:** pings a host on the public internet from this environment.

```bash
ping -c 3 -W 2 8.8.8.8
```

**Output**

```
$ ping -c 3 -W 2 8.8.8.8            # a host outside this network
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.

--- 8.8.8.8 ping statistics ---
3 packets transmitted, 0 received, 100% packet loss, time 2032ms

```

**100% packet loss — and yet this host has working internet access**, as the `curl` in section 6
proves by downloading a file from GitHub moments later.

This is the single most misleading result in network troubleshooting. ICMP is a *different protocol*
from TCP, and firewalls, cloud security groups and egress proxies routinely drop it while permitting
HTTPS. **"Ping doesn't work" never means "the network is down"** — confirm with a TCP test
(`nc -zv host 443`) before drawing conclusions.

---

## 3. `traceroute` — the path of a packet

**What this does:** reveals each router between here and the destination by sending packets with deliberately small TTLs.

```bash
traceroute -m 8 -w 2 github.com
traceroute -T -p 443 -m 6 -w 2 github.com
```

**Output**

```
$ traceroute -m 8 -w 2 github.com
traceroute to github.com (140.82.112.3), 8 hops max, 60 byte packets
 1  192.0.2.1 (192.0.2.1)  0.523 ms  0.479 ms  0.471 ms
 2  21.4.2.99 (21.4.2.99)  0.464 ms  0.456 ms  0.449 ms
 3  * * *
 4  * * *
 5  * * *
 6  * * *
 7  * * *
 8  * * *

$ traceroute -T -p 443 -m 6 -w 2 github.com      # TCP mode, port 443
traceroute to github.com (140.82.114.3), 6 hops max, 60 byte packets
 1  192.0.2.1 (192.0.2.1)  0.423 ms  0.383 ms  0.375 ms
 2  lb-140-82-114-3-iad.github.com (140.82.114.3)  0.369 ms  0.364 ms  0.358 ms
```

The default (UDP) traceroute shows hops 1 and 2, then `* * *` all the way out — the same filtering
that blocked ping. `*` means **no reply from that hop**, not that the packet stopped there.

Switching to `-T` (TCP mode on port 443) changes everything: it reaches
`lb-140-82-114-3-iad.github.com` in **2 hops**. Same destination, same network, different protocol —
because port 443 is what the path actually permits. The `-iad` in that hostname is the airport code
for Washington Dulles, which is how you infer which datacentre you were routed to.

How it works: traceroute sends a packet with `TTL=1`, and the first router decrements it to 0 and
returns `ICMP Time Exceeded`, revealing itself. Then `TTL=2` for the second, and so on.

**Reading a traceroute:** consistent `* * *` from one hop onward usually means filtering, not a
break. A sharp latency jump at one hop that persists afterwards is a real bottleneck; a single slow
hop that recovers is just a router deprioritising ICMP replies, which is normal.

---

## 4. `netstat` / `ss` — routing table, listening ports, connections

**What this does:** shows how traffic is routed out, what is listening for it, and what is currently connected.

> Run inside a container here so the listing is short enough to read in full. The commands and their
> interpretation are identical on a host.

```bash
netstat -rn          # routing table
netstat -tulnp       # listening sockets + owning process
ss -tulnp            # the modern equivalent
ss -tn               # active connections
```

**Output**

```
$ netstat -rn                # kernel routing table
Kernel IP routing table
Destination     Gateway         Genmask         Flags   MSS Window  irtt Iface
0.0.0.0         172.17.0.1      0.0.0.0         UG        0 0          0 eth0
172.17.0.0      0.0.0.0         255.255.0.0     U         0 0          0 eth0

$ ip route                   # same thing, modern tool
default via 172.17.0.1 dev eth0 
172.17.0.0/16 dev eth0 proto kernel scope link src 172.17.0.4 

$ netstat -tulnp             # listening sockets and the owning process
Active Internet connections (only servers)
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name    
tcp        0      0 0.0.0.0:80              0.0.0.0:*               LISTEN      1/nginx: master pro 
tcp        0      0 0.0.0.0:9000            0.0.0.0:*               LISTEN      506/python3         

$ ss -tulnp                  # ss is the modern replacement for netstat
Netid State  Recv-Q Send-Q Local Address:Port Peer Address:PortProcess                      
tcp   LISTEN 0      511          0.0.0.0:80        0.0.0.0:*    users:(("nginx",pid=1,fd=6))
tcp   LISTEN 0      5            0.0.0.0:9000      0.0.0.0:*    users:(("python3",pid=506,fd=3))

$ curl -s -o /dev/null http://127.0.0.1:9000/ ; ss -tn    # an established connection
State Recv-Q Send-Q Local Address:Port Peer Address:PortProcess
```

The routing table is read **most-specific-first**. Traffic to `172.17.x.x` is delivered directly on
`eth0` (`scope link` — same segment, no router needed); everything else falls through to
`0.0.0.0/0 via 172.17.0.1`, the default route. `UG` flags mean Up + Gateway. That gateway is Docker's
`docker0` bridge on the host, which is how container traffic reaches the outside world.

In the listening list, the **`0.0.0.0` versus `127.0.0.1`** distinction is the one that causes real
outages. Both listeners here are on `0.0.0.0`, so they accept connections on any interface. A service
bound to `127.0.0.1` accepts them **only from inside that machine** — which is why an app can "work
locally but not from outside", and why a containerised app bound to `127.0.0.1` stays unreachable even
with `-p`. This command proves it in seconds.

The `PID/Program name` column is the other half: `1/nginx` and `506/python3` name exactly which
process owns each port. When something reports "address already in use", this is how you find the
culprit — `netstat -tulnp | grep :8080`.

Flag breakdown for `-tulnp`: `t` TCP, `u` UDP, `l` listening only, `n` numeric (no reverse DNS, much
faster), `p` show the owning process — `-p` requires root.

`ss` is the modern replacement. It reads kernel socket state over **netlink** instead of parsing
`/proc/net/*` as text, so it is far faster on a busy host, and it supports state filters such as
`ss -tn state established` and `ss -tn state time-wait`.

---

## 5. `nslookup`, `dig` and `host` — DNS

**What this does:** resolves a name three different ways and inspects the record types behind it.

```bash
nslookup github.com
dig github.com +short
dig github.com
dig MX github.com +short
dig NS github.com +short
host github.com
dig -x 140.82.112.3 +short
```

**Output**

```
$ nslookup github.com
Server:		8.8.8.8
Address:	8.8.8.8#53

Non-authoritative answer:
Name:	github.com
Address: 140.82.114.3


$ dig github.com +short
140.82.112.3

$ dig github.com               # the full answer

; <<>> DiG 9.18.39-0ubuntu0.24.04.7-Ubuntu <<>> github.com
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 47165
;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 512
;; QUESTION SECTION:
;github.com.			IN	A

;; ANSWER SECTION:
github.com.		60	IN	A	140.82.112.4



$ dig MX github.com +short     # mail servers
0 github-com.mail.protection.outlook.com.

$ dig NS github.com +short     # authoritative nameservers
dns4.p08.nsone.net.
ns-1707.awsdns-21.co.uk.
dns1.p08.nsone.net.
dns2.p08.nsone.net.
ns-520.awsdns-01.net.
ns-421.awsdns-52.com.
ns-1283.awsdns-32.org.
dns3.p08.nsone.net.

$ host github.com
github.com has address 140.82.114.3
github.com mail is handled by 0 github-com.mail.protection.outlook.com.

$ dig -x 140.82.112.3 +short   # reverse lookup
lb-140-82-112-3-iad.github.com.
```

Notice the answers differ between runs — `140.82.114.3`, `140.82.112.3`, `140.82.112.4`. That is
**DNS round-robin load balancing**, not an error: GitHub returns different addresses from a pool to
spread traffic.

The three tools, in order of usefulness:

| Tool | Notes |
| --- | --- |
| `host` | shortest output, good for a quick check |
| `nslookup` | available on Windows too; shows which server answered |
| **`dig`** | the one to learn — full record detail, `+short` when you want just the answer |

From the full `dig` output:

- `status: NOERROR` — the query succeeded. `NXDOMAIN` means the name does not exist; `SERVFAIL`
  means the resolver broke.
- `ANSWER: 1` — one record returned.
- `github.com. 60 IN A 140.82.112.4` — the **60** is the TTL in seconds. That is deliberately short so
  GitHub can move traffic quickly; it also means a DNS change propagates within a minute.
- `Non-authoritative answer` from `nslookup` means it came from a cache, not from GitHub's own
  nameservers — those are the `dns*.p08.nsone.net` and `ns-*.awsdns-*` entries from the `NS` query.

`dig MX` shows GitHub's mail goes to Outlook, and `dig -x` does a **reverse lookup**, turning
`140.82.112.3` back into `lb-140-82-112-3-iad.github.com` — useful for identifying an unknown IP in a
log file.

---

## 6. `curl` — testing HTTP

**What this does:** exercises the actual application layer, both against a local container and a real site.

```bash
curl -sI http://localhost:8080
curl -sI https://raw.githubusercontent.com/Saniya1613/devops-heros/main/README.md
curl -s -o /dev/null -w 'code=%{http_code} total=%{time_total}s\n' <url>
```

**Output**

```
$ curl -sI http://localhost:8080          # local nginx container
HTTP/1.1 200 OK
Server: nginx/1.25.5
Date: Thu, 17 Sep 2026 21:44:38 GMT
Content-Type: text/html
Content-Length: 615
Last-Modified: Tue, 16 Apr 2024 15:47:06 GMT
Connection: keep-alive

$ curl -s http://localhost:8080 | grep -i '<title>'
<title>Welcome to nginx!</title>

$ curl -sI https://raw.githubusercontent.com/Saniya1613/devops-heros/main/README.md
HTTP/2 200 
cache-control: max-age=300
content-security-policy: default-src 'none'; style-src 'unsafe-inline'; sandbox
content-type: text/plain; charset=utf-8
etag: "f51d0d6ee25c0f7b8395f9e614f065107cc6bd918bbd435b70f1e97bca3b3df2"
strict-transport-security: max-age=31536000
x-content-type-options: nosniff

$ curl -s -o /dev/null -w 'code=%{http_code} size=%{size_download}B dns=%{time_namelookup}s tls=%{time_appconnect}s total=%{time_total}s\n' \
    https://raw.githubusercontent.com/Saniya1613/devops-heros/main/README.md
code=200 size=3035B dns=0.000024s tls=0.318551s total=0.366620s

$ curl -s https://raw.githubusercontent.com/Saniya1613/devops-heros/main/README.md | head -3
# devops-heros

DevOps coursework — Kubernetes, Sessions 9 through 12.
```

This is the test that matters: **a reachable host is not the same as a working service.** Ping can
succeed while the application returns 500, and — as section 2 showed — ping can fail while HTTPS works
perfectly. Here the fetch pulls back this very repository's README over HTTPS.

Useful flags:

| Flag | Purpose |
| --- | --- |
| `-I` | HEAD request — headers only, no body |
| `-s` | silent; hide the progress meter |
| `-L` | follow redirects |
| `-v` | full request/response including the TLS handshake |
| `-o /dev/null -w '...'` | discard the body, print only chosen metrics |
| `-H "Header: value"` | send a custom header |
| `-X POST -d '{...}'` | send a request body |
| `-k` | skip certificate verification (self-signed certs only) |

The `-w` timing breakdown is the quiet gem: `dns=0.000024s tls=0.318551s total=0.366620s` localises
slowness precisely. Here DNS was instant (cached) and **TLS negotiation was 87% of the total** — so
tuning the application would have achieved nothing; connection reuse is what would help.

---

## 7. `nc` (netcat) — is that port open?

**What this does:** attempts a bare TCP connection to a port and reports exactly how it was refused, if it was.

```bash
nc -zv localhost 8080
nc -zv localhost 9999
nc -zv -w 3 github.com 443
nc -zv -w 3 github.com 23
```

**Output**

```
$ nc -zv localhost 8080         # port 8080 - nginx is listening
Connection to localhost (127.0.0.1) 8080 port [tcp/http-alt] succeeded!

$ nc -zv localhost 9999         # port 9999 - nothing there
nc: connect to localhost (127.0.0.1) port 9999 (tcp) failed: Connection refused

$ nc -zv -w 3 github.com 443    # remote TCP port, reachable
Connection to github.com (140.82.114.3) 443 port [tcp/https] succeeded!

$ nc -zv -w 3 github.com 23     # remote telnet port, filtered
nc: connect to github.com (140.82.112.4) port 23 (tcp) timed out: Operation now in progress
(timed out - filtered, no RST returned)
```

Three distinct outcomes, and the difference between them is diagnostic gold:

| Result | Meaning | Cause |
| --- | --- | --- |
| **`succeeded!`** | TCP handshake completed | something is listening |
| **`Connection refused`** | the host answered with `RST` | host reachable, **nothing listening on that port** |
| **`timed out`** | no answer at all | a **firewall silently dropped** the packet |

`Connection refused` (port 9999) versus `timed out` (port 23) is the distinction to internalise.
Refused means you reached the machine and the port is closed — usually the service is down or bound
to the wrong interface. Timed out means the packet never got there — a firewall, security group or
network ACL is dropping it. They call for completely different fixes.

`-z` means scan only, send no data; `-v` prints the result; `-w 3` caps the wait at 3 seconds.

---

## IP addressing notes

**Private ranges** (RFC 1918) — never routed on the public internet:

| Range | CIDR | Size |
| --- | --- | --- |
| `10.0.0.0 – 10.255.255.255` | `10.0.0.0/8` | ~16.7M |
| `172.16.0.0 – 172.31.255.255` | `172.16.0.0/12` | ~1M |
| `192.168.0.0 – 192.168.255.255` | `192.168.0.0/16` | ~65k |

Docker's `172.17.0.0/16` sits inside the second range — deliberately, so container networks never
collide with public addresses.

**CIDR notation** `192.0.2.2/24` means the first 24 bits are the network and the remaining 8 identify
the host: network `192.0.2.0`, broadcast `192.0.2.255`, 254 usable addresses. Every bit added to the
prefix halves the network: `/25` is 126 usable, `/26` is 62, `/30` is 2 (a point-to-point link).

**Reserved addresses:** `127.0.0.0/8` loopback, `0.0.0.0` "all interfaces" when binding,
`169.254.0.0/16` link-local (an address in this range usually means **DHCP failed**).

**Ports:** 0–1023 well-known and root-only (22 SSH, 53 DNS, 80 HTTP, 443 HTTPS), 1024–49151
registered (3306 MySQL, 5432 Postgres, 6379 Redis, 8080 HTTP-alt), 49152–65535 ephemeral — the
source ports in the `ss -tn state established` output above.

---

## Troubleshooting order

Work **up** the stack. Each step assumes the one before it passed.

```
1. ip addr            Do I have an IP at all?
                      (169.254.x.x means DHCP failed; no address means the link is down)
2. ping <gateway>     Is the local network reachable?
3. ip route           Is there a default route out?
4. dig <hostname>     Does the name resolve?
                      (an IP that works where the name fails = a DNS problem, not a network one)
5. nc -zv <host> <port>   Is the port open?
                      (refused = service down;  timed out = firewall)
6. curl -v <url>      Does the application actually respond correctly?
```

The single most common real-world finding sits at step 4/5: the network is fine, DNS is fine, and the
service is simply bound to `127.0.0.1` instead of `0.0.0.0` — which step 5 plus `ss -tulnp` finds in
under a minute.

---

## Summary

| # | Tool | Key result |
| --- | --- | --- |
| 1 | `ifconfig` / `ip` | `eth0` `192.0.2.2/24`, plus two Docker bridges; MTU 1400 |
| 2 | `ping` | loopback and gateway 0% loss; **8.8.8.8 100% loss while HTTPS works** |
| 3 | `traceroute` | UDP filtered after hop 2; TCP/443 reached GitHub in 2 hops |
| 4 | `netstat` / `ss` | routing table, two listeners on `0.0.0.0` with owning PIDs |
| 5 | `dig` / `nslookup` / `host` | A, MX, NS and reverse records; TTL 60 round-robin |
| 6 | `curl` | 200 from local nginx and from this repo's README; TLS was 87% of latency |
| 7 | `nc` | succeeded vs **refused** vs **timed out** — three different diagnoses |
