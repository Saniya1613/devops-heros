# ---------------------------------------------------------------------------
# STAGE 1 — build
# Uses the full Go toolchain. Everything in this stage is thrown away.
# ---------------------------------------------------------------------------
FROM golang:1.22-alpine AS builder

WORKDIR /src

# Copy the module files first and resolve dependencies, so this layer is cached
# and is not invalidated every time the source changes.
COPY go.mod ./
RUN go mod download

COPY main.go ./

# CGO_ENABLED=0 produces a fully static binary with no libc dependency,
# which is what allows the final stage to be `scratch`.
# -ldflags "-s -w" strips the symbol table and DWARF debug info.
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/server main.go

# ---------------------------------------------------------------------------
# STAGE 2 — runtime
# `scratch` is the empty image: no shell, no package manager, no libc.
# ---------------------------------------------------------------------------
FROM scratch

COPY --from=builder /out/server /server

ENV PORT=8080
EXPOSE 8080

USER 65534:65534

ENTRYPOINT ["/server"]
