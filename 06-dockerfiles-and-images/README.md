# Dockerfiles & Images — Multi-Stage Builds

The same Go web service built two ways — with and without a multi-stage Dockerfile — to measure what
multi-stage actually saves. Then three different application types deployed together.

Source: [`multistage-go/`](multistage-go/) · multi-stage
[`Dockerfile`](multistage-go/Dockerfile) · single-stage
[`Dockerfile.singlestage`](multistage-go/Dockerfile.singlestage)

---

## Task 1 — Build and run the multi-stage Dockerfile

### The Dockerfile

```dockerfile
# STAGE 1 — build (thrown away)
FROM golang:1.22-alpine AS builder
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/server main.go

# STAGE 2 — runtime
FROM scratch
COPY --from=builder /out/server /server
ENV PORT=8080
EXPOSE 8080
USER 65534:65534
ENTRYPOINT ["/server"]
```

Four decisions worth explaining:

- **`AS builder`** names the stage so the second one can reach into it.
- **`COPY go.mod` before `COPY main.go`** — dependency resolution is cached and only re-runs when
  `go.mod` changes, not on every code edit. Ordering instructions from least to most frequently
  changed is the single biggest build-speed win.
- **`CGO_ENABLED=0`** produces a statically linked binary with no libc dependency. Without it the
  binary needs shared libraries that `scratch` does not have, and the container exits immediately.
- **`FROM scratch`** is the completely empty image — no shell, no package manager, no libc, no OS.

### Build

```bash
docker build -t multistage-demo:slim -f multistage-go/Dockerfile multistage-go
```

**Output** (tail)

```
$ docker build -t multistage-demo:slim -f multistage-go/Dockerfile multistage-go
#6 [builder 6/6] RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/server main.go
#7 [builder 4/6] RUN go mod download
#8 [builder 2/6] WORKDIR /src
#9 [builder 5/6] COPY main.go ./
#10 [builder 3/6] COPY go.mod ./
#11 [stage-1 1/1] COPY --from=builder /out/server /server
#12 exporting to image
#12 exporting layers done
#12 exporting manifest sha256:16849ccab6a16e5e43a39da3d938569fccc8bca696ae278fdb53d1b206c9fac9 done
#12 exporting config sha256:8bed94d75e216e30f9eaaacab27f3d90ed5aea42bc89345019e2bffb04b05cf2 done
#12 exporting attestation manifest sha256:11ea48f30cf08689c7017aa53b7da4481e9d353e78f8a3dfff459b734aae6cd7 done
#12 exporting manifest list sha256:5023d64df3c72b473ffa31830c5745901bc003f807d55f943b72b512039e0220 done
#12 naming to docker.io/library/multistage-demo:slim done
#12 DONE 0.0s
```

### The size comparison

The same application was also built **without** multi-stage, keeping the Go toolchain in the final
image:

```bash
docker build -t multistage-demo:fat -f multistage-go/Dockerfile.singlestage multistage-go
docker images --filter "reference=multistage-demo"
```

**Output**

```
$ docker images --filter 'reference=multistage-demo'
REPOSITORY        TAG       IMAGE ID       SIZE
multistage-demo   slim      5023d64df3c7   6.87MB
multistage-demo   fat       267a2617e734   441MB

$ docker images golang:1.22-alpine --format 'base builder image: {{.Size}}'
```

| Build | Size | Ratio |
| --- | --- | --- |
| `multistage-demo:fat` (single-stage) | **441 MB** | — |
| `multistage-demo:slim` (multi-stage) | **6.87 MB** | **64× smaller** |

Identical application, identical behaviour. The 434 MB difference is the Go compiler, the standard
library source, the module cache and Alpine's base filesystem — all needed to *build* the binary and
none of it needed to *run* it.

### Run on port 8080

```bash
docker run -d --name multistage-app -p 8080:8080 multistage-demo:slim
docker ps
curl -s http://localhost:8080
```

**Output**

```
$ docker run -d --name multistage-app -p 8080:8080 multistage-demo:slim
a3e67f74845e4f30a45ac7f0a1d6894b1298490c0be99f8769ebf1d911a8a900

$ docker ps --filter 'name=multistage-app'
NAMES            IMAGE                  STATUS         PORTS
multistage-app   multistage-demo:slim   Up 4 seconds   0.0.0.0:8080->8080/tcp

$ curl -s http://localhost:8080
<!DOCTYPE html><html><head><title>Multi-stage build demo</title></head><body><h1>Hello from a multi-stage Go build</h1><p>Compiled with go1.22.12, running on linux/amd64, port 8080</p><p>This binary ships in a scratch image with no OS underneath it.</p></body></html>

$ curl -s http://localhost:8080/health
ok

$ docker logs multistage-app
2026/09/17 21:50:59 listening on 0.0.0.0:8080
2026/09/17 21:51:03 served GET /
```

`Up`, serving on 8080, reporting `go1.22.12` and `linux/amd64`. A 6.87 MB image with no operating
system inside it runs a working web server.

### Inspect the image

```bash
docker image inspect multistage-demo:slim --format 'Layers: {{len .RootFS.Layers}}'
docker history multistage-demo:slim
docker exec multistage-app sh
```

**Output**

```
$ docker image inspect multistage-demo:slim --format 'Layers: {{len .RootFS.Layers}}  Size: {{.Size}} bytes'
Layers: 1  Size: 2092058 bytes
$ docker image inspect multistage-demo:fat  --format 'Layers: {{len .RootFS.Layers}}  Size: {{.Size}} bytes'
Layers: 10  Size: 91331510 bytes

$ docker history multistage-demo:slim
CREATED BY                            SIZE
ENTRYPOINT ["/server"]                0B
USER 65534:65534                      0B
EXPOSE [8080/tcp]                     0B
ENV PORT=8080                         0B
COPY /out/server /server # buildkit   4.78MB

$ docker history multistage-demo:fat | head -8
CREATED BY                                      SIZE
ENTRYPOINT ["/out/server"]                      0B
EXPOSE [8080/tcp]                               0B
ENV PORT=8080                                   0B
RUN /bin/sh -c CGO_ENABLED=0 GOOS=linux go b…   74.8MB
COPY main.go ./ # buildkit                      12.3kB
RUN /bin/sh -c go mod download # buildkit       4.1kB
COPY go.mod ./ # buildkit                       12.3kB

$ docker image inspect multistage-demo:slim --format '{{json .Config.Entrypoint}} user={{.Config.User}}'
["/server"] user=65534:65534

$ docker exec multistage-app sh      # scratch has no shell at all
OCI runtime exec failed: exec failed: unable to start container process: exec: "sh": executable file not found in $PATH
```

The layer counts tell the story: **1 layer versus 10**. `docker history` shows the slim image
consists of a single 4.78 MB `COPY` plus metadata instructions that cost 0 B, while the fat image
carries a 74.8 MB `RUN go build` layer and everything beneath it.

And the last command is the security argument in one line:

```
docker exec multistage-app sh
OCI runtime exec failed: exec: "sh": executable file not found in $PATH
```

**There is no shell in the container.** An attacker who achieves remote code execution has no
`sh`, no `curl`, no `wget`, no package manager — nothing to pivot with. Combined with
`USER 65534:65534` (the `nobody` user), the process is not root either.

The trade-off is real: you cannot `docker exec` in to debug, there are no CA certificates unless you
copy them in, and no timezone database. `gcr.io/distroless/static` is the usual middle ground — still
no shell, but with certs and zoneinfo included.

---

## Task 2 — Documentation: how multi-stage builds work

A Dockerfile may contain **multiple `FROM` instructions**. Each starts a new stage with a fresh
filesystem. Only the **last** stage becomes the image you ship; every earlier stage is discarded once
the build finishes.

```
┌─ STAGE 1: builder (golang:1.22-alpine, ~440 MB) ──┐
│  go.mod ──► go mod download                       │
│  main.go ──► go build ──► /out/server  (4.78 MB)  │
└───────────────────────┬───────────────────────────┘
                        │  COPY --from=builder
                        ▼
┌─ STAGE 2: runtime (scratch, 0 MB) ────────────────┐
│  /server                                          │
│  = final image: 6.87 MB                           │
└───────────────────────────────────────────────────┘
```

`COPY --from=<stage>` is the bridge — it reaches into an earlier stage's filesystem and copies out
only the artifacts named. Everything else in that stage is never written to the final image.

**Why it matters:**

| | Single-stage | Multi-stage |
| --- | --- | --- |
| Image size | 441 MB | 6.87 MB |
| Build tools shipped | compiler, module cache, source | none |
| Attack surface | shell, package manager, toolchain | no shell at all |
| Pull time per node | slow | near-instant |
| Source code exposed | yes, `/src/main.go` is in the image | no |

Before multi-stage builds existed (Docker 17.05), teams maintained a "builder image" plus a shell
script that ran a container, copied the artifact out, and fed it to a second `docker build`. Multi-stage
replaced all of that with one file.

**Other useful forms:**

```dockerfile
# Stop at a named stage — useful for a test-only target
docker build --target builder -t myapp:dev .

# Copy from an external image without adding it as a base
COPY --from=alpine:3.20 /etc/ssl/certs /etc/ssl/certs

# Many stages: deps -> build -> test -> runtime
FROM node:20 AS deps
FROM deps AS build
FROM build AS test
FROM nginx:alpine AS runtime
```

Typical runtime bases, from strictest to most convenient: `scratch` (static binaries only) →
`gcr.io/distroless/static` (certs, no shell) → `alpine` (shell, apk, ~7 MB) → `debian:slim`.

---

## Task 3 — Deploy three different application types

Three deliberately different runtimes, deployed together with one command via
[`docker-compose.yml`](docker-compose.yml):

| Service | Type | Image | Port |
| --- | --- | --- | --- |
| `web` | **static** — nginx, no app runtime | `hello-nginx:1.0` | 8091 |
| `api` | **interpreted** — Python, source shipped | `hello-python:1.0` | 8092 |
| `service` | **compiled** — Go, multi-stage into `scratch` | `multistage-demo:slim` | 8093 |

```bash
docker compose up -d
docker compose ps
curl -s http://localhost:8091   # and 8092, 8093
docker compose down
```

**Output**

```
$ docker compose up -d
 Container stack-service Creating 
 Container stack-service Created 
 Container stack-api Created 
 Container stack-web Created 
 Container stack-web Starting 
 Container stack-service Starting 
 Container stack-api Starting 
 Container stack-service Started 
 Container stack-web Started 
 Container stack-api Started 

$ docker compose ps
NAME            IMAGE                  STATUS         PORTS
stack-api       hello-python:1.0       Up 6 seconds   0.0.0.0:8092->5000/tcp
stack-service   multistage-demo:slim   Up 6 seconds   0.0.0.0:8093->8080/tcp
stack-web       hello-nginx:1.0        Up 6 seconds   0.0.0.0:8091->80/tcp

$ curl -s http://localhost:8091 | grep '<h1>'   # static  (nginx)
  <h1>Hello World from Nginx</h1>
$ curl -s http://localhost:8092 | grep -o '<h1>.*</h1>'   # interpreted (python)
<h1>Hello World from Python</h1>
$ curl -s http://localhost:8093 | grep -o '<h1>.*</h1>'   # compiled (go/scratch)
<h1>Hello from a multi-stage Go build</h1>

$ docker compose down
 Container stack-web Removed 
 Container stack-api Stopped 
 Container stack-api Removing 
 Container stack-api Removed 
 Network 06-dockerfiles-and-images_default Removing 
 Network 06-dockerfiles-and-images_default Removed 
```

All three came up from a single command and all three responded. Compose also created a dedicated
network (`06-dockerfiles-and-images_default`) and removed it on teardown, so the services could reach
each other by service name — `http://api:5000` from inside `web`, without any IP addresses.

The five individual applications (nginx, Apache, Python, Node.js, Java) are built and run separately
in [05-docker-fundamentals](../05-docker-fundamentals/).

---

## What I understood about multi-stage builds

**Build-time and run-time dependencies are different sets, and only one belongs in the image.** A
compiler, test framework and package manager are needed to produce the artifact and are pure liability
once it exists.

**Size is not vanity.** A 441 MB image is pulled on every node, on every scale-up, on every rollout.
At 6.87 MB the same deploy is effectively instant — which is exactly what makes the rolling updates in
[session10](../session10-k8s-core-objects/) finish in seconds.

**Layer ordering decides your build times.** `COPY go.mod` before `COPY main.go` means editing source
does not re-download dependencies. Get this backwards and every one-character change triggers a full
dependency install.

**`scratch` is a security posture, not just a size trick.** No shell means no interactive
exploitation. The cost is that debugging must happen through logs, metrics and traces rather than
`docker exec` — which is the right habit for production anyway.

**`CGO_ENABLED=0` is the detail that makes it work.** A dynamically linked binary in `scratch` fails
instantly with "no such file or directory" — which is confusingly reported about a file that *is*
there. The missing file is the dynamic linker, not the binary.

---

## Summary

| # | Task | Key result |
| --- | --- | --- |
| 1 | Multi-stage build, run on 8080 | **6.87 MB vs 441 MB** — 64× smaller, 1 layer vs 10 |
| 1b | Image inspection | no shell in `scratch`; runs as UID 65534, not root |
| 2 | Documentation | stage mechanics, `COPY --from`, `--target`, runtime base choices |
| 3 | Three application types | static + interpreted + compiled, deployed together with Compose |
