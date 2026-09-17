# Docker Fundamentals

Five "Hello World" web applications, each in a different language or server, containerised and run
side by side on five ports.

Docker Engine 29.4.3 on Ubuntu 24.04. Every command below was actually executed and the output is
pasted verbatim.

| App | Directory | Base image | Container port | Host port |
| --- | --- | --- | --- | --- |
| Nginx (static) | [`nginx-app/`](nginx-app/) | `nginx:1.25-alpine` | 80 | 8081 |
| Apache (static) | [`apache-app/`](apache-app/) | `httpd:2.4-alpine` | 80 | 8082 |
| Python | [`python-app/`](python-app/) | `python:3.12-alpine` | 5000 | 8083 |
| Node.js | [`nodejs-app/`](nodejs-app/) | `node:20-alpine` | 3000 | 8084 |
| Java | [`java-app/`](java-app/) | `eclipse-temurin:21` | 7000 | 8085 |

---

## Step 1 — Build the images

**What this does:** builds one image per application from its own Dockerfile.

```bash
docker build -t hello-nginx:1.0  ./nginx-app
docker build -t hello-apache:1.0 ./apache-app
docker build -t hello-python:1.0 ./python-app
docker build -t hello-nodejs:1.0 ./nodejs-app
docker build -t hello-java:1.0   ./java-app
docker images --filter "reference=hello-*"
```

**Output**

```
$ docker build -t hello-nginx:1.0  ./nginx-app
$ docker build -t hello-apache:1.0 ./apache-app
$ docker build -t hello-python:1.0 ./python-app
$ docker build -t hello-nodejs:1.0 ./nodejs-app
$ docker build -t hello-java:1.0   ./java-app

$ docker images --filter 'reference=hello-*'
REPOSITORY     TAG       IMAGE ID       SIZE
hello-java     1.0       d14985e35e78   286MB
hello-nodejs   1.0       818412f7f133   193MB
hello-python   1.0       fd728dfc2238   82.9MB
hello-apache   1.0       fb8e3a5fd718   96.1MB
hello-nginx    1.0       f8ea406b5ae0   74.1MB
```

The size spread is the interesting part — **74 MB for nginx against 286 MB for Java**, serving
identical content. That is the runtime you are shipping, not your code: a JVM is simply larger than
an nginx binary. It is also why every base image here is `-alpine`; the Debian variants are typically
3–5× bigger.

### The two static servers

Both are pure `COPY` — no build step:

```dockerfile
FROM nginx:1.25-alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
```

There is no `CMD`, because the base image already declares one. The only difference for Apache is the
web root: `/usr/local/apache2/htdocs/`.

### The interpreted apps

```dockerfile
FROM python:3.12-alpine
WORKDIR /app
COPY app.py .
ENV PORT=5000
EXPOSE 5000
CMD ["python", "app.py"]
```

`WORKDIR` creates and enters the directory. `ENV PORT=5000` sets a default the app reads, so the port
can be overridden at runtime with `docker run -e PORT=…` without rebuilding.

### The compiled app — a two-stage build

Java needs compiling, and that is where [`java-app/Dockerfile`](java-app/Dockerfile) differs:

```dockerfile
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /build
COPY Main.java .
RUN javac Main.java

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=builder /build/Main.class .
CMD ["java", "Main"]
```

The first stage has the **JDK** and compiles the source. The second starts from the **JRE** and copies
in only the resulting `.class` file. `javac` and the source never reach the final image — smaller, and
one less thing an attacker can use. Multi-stage builds are explored properly in
[06-dockerfiles-and-images](../06-dockerfiles-and-images/).

---

## Step 2 — Run the containers

**What this does:** starts all five detached, each publishing its port to a different host port.

```bash
docker run -d --name hello-nginx  -p 8081:80   hello-nginx:1.0
docker run -d --name hello-apache -p 8082:80   hello-apache:1.0
docker run -d --name hello-python -p 8083:5000 hello-python:1.0
docker run -d --name hello-nodejs -p 8084:3000 hello-nodejs:1.0
docker run -d --name hello-java   -p 8085:7000 hello-java:1.0
```

**Output**

```
$ docker run -d --name hello-nginx  -p 8081:80   hello-nginx:1.0
da89fc3f87138977b3817db9205e9fee0952bd5a1629c1ebae475817241b10d4
$ docker run -d --name hello-apache -p 8082:80   hello-apache:1.0
a52b11a7d5af8aefee0b2470e042c1da4ec2bebdb291ca071dacc59701a883ed
$ docker run -d --name hello-python -p 8083:5000 hello-python:1.0
ee39735c399369d835ba65b971f0c39e57889f895d64cb7eff422111d3136a76
$ docker run -d --name hello-nodejs -p 8084:3000 hello-nodejs:1.0
86eca006c5ddd3c8b7ce9fb2c288743b91086e56a984945181fa35a4664c7eb5
$ docker run -d --name hello-java   -p 8085:7000 hello-java:1.0
d1dd201162318cac7fd85fdf0906517acae70d6ca58f4dbcfc9727c48116ff47
```

Each command returns the full 64-character container ID. Flags used:

- **`-d`** detached — run in the background and return the prompt.
- **`--name`** a stable name, so commands can say `hello-nginx` instead of a hash.
- **`-p HOST:CONTAINER`** publish a port. `-p 8083:5000` means **host 8083 → container 5000**.

Nginx and Apache both listen on **80 inside their containers** and that is fine — container ports are
namespaced, so they do not collide. Only the *host* ports must be unique, which is why they are
mapped to 8081 and 8082.

---

## Step 3 — Verify the containers are running

```bash
docker ps
```

**Output**

```
$ docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
NAMES          IMAGE                       STATUS          PORTS
hello-java     hello-java:1.0              Up 10 seconds   0.0.0.0:8085->7000/tcp
hello-nodejs   hello-nodejs:1.0            Up 10 seconds   0.0.0.0:8084->3000/tcp
hello-python   hello-python:1.0            Up 11 seconds   0.0.0.0:8083->5000/tcp
hello-apache   hello-apache:1.0            Up 11 seconds   0.0.0.0:8082->80/tcp
hello-nginx    hello-nginx:1.0             Up 11 seconds   0.0.0.0:8081->80/tcp
netdemo        nginx:1.25-alpine           Up 4 minutes    0.0.0.0:8080->80/tcp
sysd           jrei/systemd-ubuntu:24.04   Up 9 minutes    
```

All five `Up`. The `PORTS` column reads `0.0.0.0:8085->7000/tcp` — host 8085 forwards to container
7000, and `0.0.0.0` means it accepts connections on any host interface, not just loopback.

(`netdemo` and `sysd` in that listing are containers from the
[networking](../03-networking/) and [Linux](../01-linux-fundamentals/) sections.)

---

## Step 4 — Verify Hello World is displayed

**What this does:** requests each app and checks the response actually comes from the right runtime.

```bash
curl -s http://localhost:8081 | grep -E '<h1>|<p>'   # ... and 8082-8085
```

**Output**

```
$ curl -s http://localhost:8081 | grep -E '<h1>|<p>'
  <h1>Hello World from Nginx</h1>
  <p>Served by an nginx container on port 8081.</p>

$ curl -s http://localhost:8082 | grep -E '<h1>|<p>'
  <h1>Hello World from Apache</h1>
  <p>Served by an httpd container on port 8082.</p>

$ curl -s http://localhost:8083 | grep -E '<h1>|<p>'
<!DOCTYPE html><html><head><title>Hello World - Python</title></head><body><h1>Hello World from Python</h1><p>http.server on port 5000, path /</p></body></html>

$ curl -s http://localhost:8084 | grep -E '<h1>|<p>'
<!DOCTYPE html><html><head><title>Hello World - Node.js</title></head><body><h1>Hello World from Node.js</h1><p>Node v20.20.2 on port 3000, path /</p></body></html>

$ curl -s http://localhost:8085 | grep -E '<h1>|<p>'
<!DOCTYPE html><html><head><title>Hello World - Java</title></head><body><h1>Hello World from Java</h1><p>JDK 21.0.12 on port 7000, path /</p></body></html>

```

All five respond, and the dynamic ones report their own runtime version — **Node v20.20.2**,
**JDK 21.0.12** — which proves the response is genuinely generated inside that container and not
served from somewhere else.

Note what each app reports as its port: the Node app says `port 3000`, not 8084. **Inside the
container it only ever sees its own port**; the 8084 mapping exists purely on the host side.

### Logs and processes

```bash
docker logs hello-python
docker exec hello-python ps aux
```

**Output**

```
$ docker logs hello-python
[python-app] listening on 0.0.0.0:5000
[python-app] "GET / HTTP/1.1" 200 -

$ docker logs hello-nodejs
[nodejs-app] listening on 0.0.0.0:3000
[nodejs-app] GET /

$ docker logs hello-java
[java-app] listening on 0.0.0.0:7000
[java-app] GET /

$ docker exec hello-python ps aux      # only the app runs inside - no init system
PID   USER     TIME  COMMAND
    1 root      0:00 python app.py
   13 root      0:00 ps aux

$ docker inspect hello-nginx --format '{{.NetworkSettings.Networks.bridge.IPAddress}}'
172.17.0.4

$ docker exec hello-nginx cat /usr/share/nginx/html/index.html | head -4   # the COPY landed
<!DOCTYPE html>
<html>
<head><title>Hello World - Nginx</title></head>
<body>
```

Two things worth drawing out:

- The logs contain the startup line **and** the request served by the `curl` above. `docker logs`
  captures stdout/stderr — which is why containerised apps should log to stdout rather than to a file
  inside the container, where nothing can collect them.
- `docker exec … ps aux` shows **PID 1 is `python app.py` itself**. There is no init system, no
  systemd, no sshd. A container is one process in its own namespaces, not a small virtual machine.
  That is also why PID 1 receives `SIGTERM` directly on `docker stop` and must handle it.

`docker inspect` gives the container's own IP on the default bridge, `172.17.0.4` — reachable from
the host and from other containers on that bridge, but not from outside without `-p`.

---

## Step 5 — Clean up

```bash
docker stop hello-nginx hello-apache hello-python hello-nodejs hello-java
docker rm   hello-nginx hello-apache hello-python hello-nodejs hello-java
```

**Output**

```
$ docker stop hello-nginx hello-apache hello-python hello-nodejs hello-java
hello-nginx
hello-apache
hello-python
hello-nodejs
hello-java

$ docker rm hello-nginx hello-apache hello-python hello-nodejs hello-java
hello-nginx
hello-apache
hello-python
hello-nodejs
hello-java

$ docker ps --filter 'name=hello-'      # all gone
CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES

$ docker images --filter 'reference=hello-*' --format '{{.Repository}}:{{.Tag}}'   # images remain
hello-java:1.0
hello-nodejs:1.0
hello-python:1.0
hello-apache:1.0
hello-nginx:1.0
```

`docker ps` is empty afterwards, but `docker images` still lists all five. **Stopping and removing a
container does not remove its image** — the image is the read-only template, the container is a
writable layer on top of it. Removing images is `docker rmi`, and `docker system prune` sweeps
unused containers, networks and dangling images.

`docker stop` sends `SIGTERM` and waits 10 seconds before `SIGKILL`, giving the app a chance to
finish in-flight requests. `docker kill` skips straight to `SIGKILL`.

---

## What I understood

**An image is a template, a container is a running instance.** The same image can back many
containers at once; each gets its own writable layer, and anything written there is lost when the
container is removed. That is why data belongs in volumes or bind mounts
([07-docker-networking](../07-docker-networking/) covers this).

**`EXPOSE` documents, `-p` publishes.** `EXPOSE 5000` in a Dockerfile opens nothing — it is metadata
telling a human (and `docker run -P`) which port the app uses. Without `-p 8083:5000` the app is
unreachable from the host.

**Bind to `0.0.0.0`, never `127.0.0.1`.** Every app here listens on `0.0.0.0`. A server bound to
`127.0.0.1` inside a container is reachable only from within that container's own network namespace,
so `-p` forwards to nothing and you get a connection reset. This is one of the most common first-time
Docker bugs.

**Layers are cached by instruction.** Docker reuses a layer when the instruction and its inputs are
unchanged. Copying source before installing dependencies invalidates the dependency layer on every
code change — which is why real Dockerfiles copy the manifest, install, and only then copy the source.

**Alpine and multi-stage are how images stay small.** 74 MB versus 286 MB is the difference between a
fast deploy and a slow one, across every node that has to pull it.

---

## Summary

| # | Step | Result |
| --- | --- | --- |
| 1 | Build five images | 74 MB (nginx) to 286 MB (Java); Java used a two-stage build |
| 2 | Run five containers | all detached, ports 8081–8085 published |
| 3 | Verify running | all five `Up`, port mappings correct |
| 4 | Verify Hello World | all five responded, reporting their own runtime versions |
| 5 | Clean up | containers stopped and removed; images retained |
