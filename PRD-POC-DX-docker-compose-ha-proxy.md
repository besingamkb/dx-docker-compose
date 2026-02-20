# PRD: Minimal HAProxy POC for DX Docker-Compose

**Document Version:** 1.0
**Date:** February 20, 2026
**Purpose:** Research POC to implement load balancing, path routing, cookie management, sticky sessions, and user session tracking in the dx-docker-compose setup.
**Target Repo:** https://github.com/HCL-TECH-SOFTWARE/dx-docker-compose

---

## 1. Objective

Implement a minimal, working HAProxy configuration in the dx-docker-compose environment that demonstrates the five core capabilities from the Helm chart HAProxy approach:

1. **Load Balancing** — Distribute traffic across multiple Core instances
2. **Path Routing** — Route requests to the correct backend service by URL path
3. **Cookie Management** — Manage session affinity cookies with proper security attributes
4. **Sticky Sessions** — Pin authenticated users to the same Core instance
5. **User Session Tracking** — Track per-user request rates via stick tables

This is a **research POC** — not production-ready. The goal is to prove the concepts work in a docker-compose environment with minimal changes.

---

## 2. Scope

### In Scope
- Replace the existing `haproxy.cfg` with an enhanced version
- Scale `dx-core` to 2 replicas to demonstrate load balancing and sticky sessions
- All 5 capabilities working end-to-end
- HAProxy stats dashboard for visual verification

### Out of Scope
- SSL/TLS termination (keep HTTP-only for simplicity)
- HSTS, CSP, or other security headers
- Friendly URL rewriting for DAM
- Runtime Controller, Search Middleware, AI Integrator, People Service backends
- Config Wizard / DXConnect routing
- WebEngine support
- HPA auto-scaling
- Custom/delete header management
- Prometheus metrics exporter (use stats dashboard instead)

---

## 3. Prerequisites

- Working dx-docker-compose environment (all services start successfully)
- Docker Compose v2+ (for `deploy.replicas` support)
- DX docker images loaded per the dx-docker-compose README

---

## 4. Implementation

### 4.1 Changes to `dx.yaml`

Scale the `core` service to **2 replicas** and remove the `container_name` (required for scaling). Also remove the fixed port mappings on core since HAProxy will front it.

```yaml
# NOTE: Since this POC keeps the existing 2-service approach (core + core2),
# the dx.yaml core services remain unchanged. The deploy.replicas approach
# below is NOT used. Keep original volumes as-is:
#   core:  ./volumes/core/wp_profile:/opt/HCL/wp_profile
#   core2: ./volumes/core2/wp_profile:/opt/HCL/wp_profile
services:
  core:
    # REMOVE: container_name: dx-core  (container_name prevents scaling)
    image: ${DX_DOCKER_IMAGE_CORE:?'Missing docker image environment parameter'}
    volumes:
      - ./volumes/core/wp_profile/logs:/opt/HCL/wp_profile/logs
      - ./volumes/core/cw_profile/logs:/opt/HCL/AppServer/profiles/cw_profile/logs
    deploy:
      replicas: 2
    networks:
      - default
```

> **Note:** With `container_name` removed and `replicas: 2`, Docker Compose will create containers named `dx-docker-compose-core-1` and `dx-docker-compose-core-2`. The service name `core` will resolve via Docker DNS to both container IPs.

The `haproxy` service remains mostly the same but add the stats port:

```yaml
  haproxy:
    image: ${DX_DOCKER_IMAGE_HAPROXY:?'Missing docker image environment parameter'}
    container_name: dx-haproxy
    volumes:
      - ./haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg
    ports:
      - 80:8081
      - 8404:8404   # Stats dashboard
    networks:
      - default
```

All other services (`ringapi`, `dam`, `cc`, `image-processor`, etc.) remain unchanged.

---

### 4.2 New `haproxy.cfg`

Replace the existing `haproxy.cfg` with the following. Each section is annotated with which capability it addresses.

```haproxy
# =============================================================================
# DX Docker-Compose HAProxy POC
# Demonstrates: Load Balancing, Path Routing, Cookie Management,
#               Sticky Sessions, User Session Tracking
# =============================================================================

# ------------------------------------------------------------------------------
# GLOBAL SETTINGS
# ------------------------------------------------------------------------------
global
    maxconn 50000
    log stdout format raw local0 info
    nbthread 4
    # Stats socket for admin access (optional, useful for debugging stick tables)
    stats socket /var/run/haproxy.sock mode 660 level admin

# ------------------------------------------------------------------------------
# DEFAULTS
# ------------------------------------------------------------------------------
defaults
    timeout connect 10s
    timeout client 1200s
    timeout server 1200s
    log global
    mode http
    option httplog
    # [LOAD BALANCING] Failover: re-dispatch to another server if current one is down
    option redispatch
    # [LOAD BALANCING] Algorithm: roundrobin is fine for this POC since we only have 2 DX Core instances.
    # leastconn would only become meaningful with 3+ servers and uneven session durations.
    balance leastconn
    # [LOAD BALANCING] Custom log format with source IP removed (privacy)
    log-format "[%tr] %ft %b/%s %TR/%Tw/%Tc/%Tr/%Ta %ST %B %CC %CS %tsc %ac/%fc/%bc/%sc/%rc %sq/%bq %hr %hs %{+Q}r"

# ------------------------------------------------------------------------------
# DNS RESOLVER
# Uses Docker's built-in DNS to discover container IPs by service name
# ------------------------------------------------------------------------------
resolvers docker-dns
    nameserver dns 127.0.0.11:53
    resolve_retries 3
    timeout resolve 1s
    timeout retry 1s
    accepted_payload_size 8192
    hold valid 5s

# ------------------------------------------------------------------------------
# [USER SESSION TRACKING] Persist stick tables across HAProxy reloads
# ------------------------------------------------------------------------------
peers localPeer
    peer local 127.0.0.1:10000

# ------------------------------------------------------------------------------
# FRONTEND: Stats Dashboard
# Provides visual verification of backends, sessions, and stick tables
# ------------------------------------------------------------------------------
frontend stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 10s

# ------------------------------------------------------------------------------
# FRONTEND: Health Probe
# Returns 200 OK for container health checks
# NOTE: Not needed for this POC (no orchestrator checking probes).
# Kept in config but port 8888 is not exposed in dx.yaml.
# The stats dashboard (port 8404) is more useful for POC debugging.
# ------------------------------------------------------------------------------
frontend probe
    no log
    bind *:8888
    http-request return status 200 content-type "text/plain" string "OK"

# ------------------------------------------------------------------------------
# FRONTEND: Main DX Traffic
# [PATH ROUTING] + [USER SESSION TRACKING] + [STICKY SESSIONS]
# ------------------------------------------------------------------------------
frontend dx
    bind :8081

    # ------------------------------------------------------------------
    # [PATH ROUTING] Route requests to correct backend by URL path
    # ------------------------------------------------------------------
    use_backend dam if { path -m reg ^/dx/(api|ui)/dam/ }
    # NOTE: /dx/ui/picker/ route not needed for this POC since focus is on Core backend capabilities
    # use_backend dam if { path_beg /dx/ui/picker/ }
    use_backend content if { path_beg /dx/ui/content/ }
    use_backend image-processor if { path_beg /dx/api/image-processor/ }
    use_backend ring-api if { path_beg /dx/api/core/ }

    # ------------------------------------------------------------------
    # [USER SESSION TRACKING] Track per-user request rates
    # ------------------------------------------------------------------
    # Build a unique fingerprint per user: source IP + User-Agent + X-Forwarded-For
    stick-table type string len 180 size 1m expire 30m store http_req_rate(30m),gpc0 peers localPeer
    http-request set-header X-Concat --%[src]_%[req.fhdr(User-Agent)]_%[req.fhdr(X-Forwarded-For,-1)]--
    http-request track-sc0 req.fhdr(X-Concat)

    # ------------------------------------------------------------------
    # [PATH ROUTING] Default: all unmatched traffic goes to Core
    # ------------------------------------------------------------------
    default_backend core-dx-home

# ------------------------------------------------------------------------------
# BACKEND: Core DX (scaled to 2 replicas)
# [LOAD BALANCING] + [STICKY SESSIONS] + [COOKIE MANAGEMENT]
# ------------------------------------------------------------------------------
backend core-dx-home
    # [STICKY SESSIONS] Detect session-related cookies in backend responses
    acl has_jsession_cookie res.cook(JSESSIONID) -m found
    acl has_ltpa_cookie res.cook(LtpaToken2) -m found

    # [COOKIE MANAGEMENT] DxSessionAffinity cookie configuration
    # - insert: HAProxy creates the cookie (not the app)
    # - indirect: cookie is not passed to the backend server
    # - httponly: not accessible via JavaScript
    # - dynamic: HAProxy auto-generates a unique value per server
    # - nocache: adds Cache-Control: no-cache to responses that set this cookie
    cookie DxSessionAffinity insert indirect httponly dynamic nocache

    # [LOAD BALANCING] Dynamic cookie key for generating per-server values
    dynamic-cookie-key dx-docker-compose

    # [LOAD BALANCING] Use server-template for dynamic discovery of Core replicas
    # Docker DNS resolves "core" to all container IPs for the scaled service
    # "2" = max number of servers to discover (matches replicas: 2)
    server-template core-dx-home 2 core:10039 check resolvers docker-dns init-addr none

# ------------------------------------------------------------------------------
# BACKEND: Digital Asset Management (single instance)
# [PATH ROUTING]
# ------------------------------------------------------------------------------
backend dam
    server dam dam:3001 check resolvers docker-dns init-addr none

# ------------------------------------------------------------------------------
# BACKEND: Content Composer (single instance)
# [PATH ROUTING]
# ------------------------------------------------------------------------------
backend content
    server content cc:3000 check resolvers docker-dns init-addr none

# ------------------------------------------------------------------------------
# BACKEND: Image Processor (single instance)
# [PATH ROUTING]
# ------------------------------------------------------------------------------
backend image-processor
    server image-processor image-processor:8080 check resolvers docker-dns init-addr none

# ------------------------------------------------------------------------------
# BACKEND: Ring API (single instance)
# [PATH ROUTING]
# ------------------------------------------------------------------------------
backend ring-api
    server ring-api ringapi:3000 check resolvers docker-dns init-addr none
```

---

### 4.3 Key Differences from Original `haproxy.cfg`

| Area | Original | POC |
|---|---|---|
| Load balancing algorithm | `balance roundrobin` (explicit) | `balance leastconn` (note: `roundrobin` is also fine for this POC since only 2 DX Core instances are needed; `leastconn` becomes more relevant with 3+ servers) |
| Failover | None | `option redispatch` |
| Core backend | 2 static servers: `server core1 dx-core:10039` + `server core2 dx-core-2:10039` | Keeping 2 static servers for this POC (note: `server-template` with `deploy.replicas` is an alternative for dynamic discovery but not needed for a 2-instance POC) |
| Sticky sessions | `cookie DXSRVID insert indirect nocache` with static per-server values | `cookie DxSessionAffinity insert indirect httponly dynamic nocache` (upgrade: adds `httponly` for security, `dynamic` for auto-generated server values needed by `server-template`) |
| Session cookie detection | None | ACLs for `JSESSIONID` and `LtpaToken2` |
| User session tracking | None | Stick table with `X-Concat` fingerprint, `http_req_rate(30m)`, `gpc0` |
| Stick table persistence | None | `peers localPeer` |
| Stats dashboard | None | Frontend on port 8404 (`/stats`) |
| Health probe | None | Frontend on port 8888 (returns 200) — not needed for POC, port not exposed in `dx.yaml` |
| Path routing | 4 routes | 4 routes (unchanged; POC focuses on Core backend capabilities) |
| Log format | Default (includes IPs) | Custom (IPs removed) |
| DNS resolver | `parse-resolv-conf` | Explicit Docker DNS `127.0.0.11:53` with short TTL for replica discovery |
| Backend server names | Hardcoded container names (`dx-core`, `dx-dam`, etc.) | Docker Compose service names (`core`, `dam`, etc.) |

---

## 5. Verification Steps

### 5.1 Start the Environment

```bash
docker-compose -f dx.yaml up -d
```

Verify 2 core containers are running:
```bash
docker ps | grep core
```
Expected: Two containers like `dx-docker-compose-core-1` and `dx-docker-compose-core-2`.

### 5.2 Verify Path Routing

Test each route returns a response (not a 503):

```bash
# Core (default backend)
curl -s -o /dev/null -w "%{http_code}" http://localhost/wps/portal

# DAM
curl -s -o /dev/null -w "%{http_code}" http://localhost/dx/api/dam/v1/collections

# Content Composer
curl -s -o /dev/null -w "%{http_code}" http://localhost/dx/ui/content/

# Image Processor
curl -s -o /dev/null -w "%{http_code}" http://localhost/dx/api/image-processor/

# Ring API
curl -s -o /dev/null -w "%{http_code}" http://localhost/dx/api/core/
```

### 5.3 Verify Load Balancing

Open the stats dashboard at **http://localhost:8404/stats** and confirm:
- `core-dx-home` backend shows **2 servers** (green = healthy)
- Both servers have non-zero session counts after sending traffic

Alternatively, send multiple requests and check which server handles them:
```bash
for i in $(seq 1 10); do
  curl -s -o /dev/null -w "Request $i: %{http_code}\n" http://localhost/wps/portal
done
```
In the stats dashboard, both `core-dx-home/core-dx-home1` and `core-dx-home/core-dx-home2` should show sessions.

### 5.4 Verify Sticky Sessions & Cookie Management

1. Make an initial request and capture the response cookies:
```bash
curl -v -c cookies.txt http://localhost/wps/portal 2>&1 | grep -i "set-cookie"
```

2. Look for the `DxSessionAffinity` cookie in the response headers or `cookies.txt`.

3. Make subsequent requests with the cookie and verify they go to the same server:
```bash
# Send 5 requests with the affinity cookie
for i in $(seq 1 5); do
  curl -s -b cookies.txt -o /dev/null -w "Request $i: %{http_code}\n" http://localhost/wps/portal
done
```

4. In the stats dashboard, confirm that only **one** of the two core servers received all 5 requests (the one pinned by the cookie).

### 5.5 Verify User Session Tracking

Access the stats dashboard at **http://localhost:8404/stats** — the stick table entries are visible in the frontend `dx` section.

Alternatively, use the HAProxy socket to query the stick table directly:
```bash
docker exec dx-haproxy sh -c "echo 'show table dx' | socat stdio /var/run/haproxy.sock"
```

Expected output shows tracked entries with request rates:
```
# table: dx, type: string, size:1048576, used:1
0x... key=--172.18.0.1_curl/8.1.2_-- use=0 exp=1799230 ...  http_req_rate(30000)=5 gpc0=0
```

### 5.6 Verify Health Probe

```bash
curl -s http://localhost:8888/
```
Expected: `OK` with HTTP 200.

> **Note:** Port 8888 needs to be exposed in `dx.yaml` if you want to test from the host. Otherwise it's only accessible within the Docker network. For this POC, the probe is primarily for internal container health checks.

---

## 6. How Each Capability Maps to Config

| Capability | Config Directives | Where to Verify |
|---|---|---|
| **Load Balancing** | `balance leastconn`, `server-template ... 2`, `option redispatch` | Stats dashboard → `core-dx-home` backend shows 2 servers with distributed sessions |
| **Path Routing** | `use_backend ... if { path_beg ... }`, `default_backend` | `curl` each path → correct backend responds |
| **Cookie Management** | `cookie DxSessionAffinity insert indirect httponly dynamic nocache` | `curl -v` → `Set-Cookie: DxSessionAffinity=...` in response with `HttpOnly` attribute |
| **Sticky Sessions** | `cookie DxSessionAffinity ...` + `dynamic-cookie-key` | Send requests with cookie → all go to same server in stats |
| **User Session Tracking** | `stick-table`, `X-Concat` header, `track-sc0` | `show table dx` via socket → entries with `http_req_rate` values |

---

## 7. Known Limitations of This POC

1. **No SSL** — All traffic is HTTP. The Helm chart defaults to HTTPS with SSL termination at HAProxy.
2. **No `Secure`/`SameSite` on cookies** — These require HTTPS to be meaningful.
3. **Core replicas share no state** — DX Core is stateful (WebSphere). Two independent Core instances will have separate sessions. This POC demonstrates HAProxy's routing behavior, not DX Core clustering.
4. **Static replica count** — `server-template 2` is hardcoded. In the Helm chart this is dynamic based on HPA settings.
5. **No rate limiting enforcement** — The stick table tracks rates but no ACL rules deny/throttle based on them. This is also the case in the Helm chart (infrastructure is in place, enforcement is not).
6. **Single-instance backends** — DAM, CC, Image Processor, Ring API are not scaled. Only Core is scaled to demonstrate load balancing.
7. **Docker DNS TTL** — Docker's internal DNS may cache IPs. The `hold valid 5s` setting mitigates this but is not instant.
