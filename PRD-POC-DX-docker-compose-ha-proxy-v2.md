# PRD: Minimal HAProxy POC for DX Docker-Compose

**Document Version:** 2.0  
**Date:** February 20, 2026  
**Purpose:** Research POC to enhance HAProxy in the dx-docker-compose setup with session tracking, monitoring, and security improvements.  
**Target Repo:** https://github.com/HCL-TECH-SOFTWARE/dx-docker-compose

---

## 1. Objective

Enhance the existing HAProxy configuration in the dx-docker-compose environment with capabilities that don't yet exist, while keeping the current working setup intact.

### What Already Works (no changes needed)
- **Load Balancing** — `balance roundrobin` across 2 Core instances (`core` + `core2`)
- **Path Routing** — 4 routes to DAM, Content Composer, Image Processor, Ring API
- **Sticky Sessions** — `DXSRVID` cookie with static per-server values

### What This POC Adds
1. **Cookie Security** — Add `httponly` flag to existing `DXSRVID` cookie
2. **User Session Tracking** — Stick tables to track per-user request rates
3. **Stats Dashboard** — Visual monitoring of backends, sessions, and stick tables
4. **Failover** — `option redispatch` to re-route if a server goes down
5. **Improved Logging** — Custom log format with source IPs removed for privacy
6. **Health Probe** — Lightweight endpoint for internal container health checks

This is a **research POC** — not production-ready.

---

## 2. Scope

### In Scope
- Enhance the existing `haproxy.cfg` with new capabilities
- Keep existing 2-core setup (`core` + `core2` as separate services)
- HAProxy stats dashboard for visual verification
- All enhancements working end-to-end

### Out of Scope
- SSL/TLS termination (keep HTTP-only for simplicity)
- HSTS, CSP, or other security headers
- `deploy.replicas` / `server-template` (keeping hardcoded servers)
- Scaling beyond 2 Core instances
- Friendly URL rewriting for DAM
- Runtime Controller, Search Middleware, AI Integrator, People Service backends
- Config Wizard / DXConnect routing
- WebEngine support
- HPA auto-scaling
- Prometheus metrics exporter (use stats dashboard instead)

---

## 3. Prerequisites

- Working dx-docker-compose environment (all services start successfully)
- Docker Compose v2+
- DX docker images loaded per the dx-docker-compose README

---

## 4. Implementation

### 4.1 Changes to `dx.yaml`

**Only one change:** Add the stats dashboard port to the `haproxy` service.

```yaml
  haproxy:
    image: ${DX_DOCKER_IMAGE_HAPROXY:?'Missing docker image environment parameter'}
    container_name: dx-haproxy
    volumes:
      - ./haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg
    ports:
      - 80:8081
      - 8404:8404   # NEW: Stats dashboard
    networks:
      - default
```

> **Note:** All other services (`core`, `core2`, `ringapi`, `dam`, `cc`, `image-processor`, etc.) remain **completely unchanged**.

---

### 4.2 New `haproxy.cfg`

Replace the existing `haproxy.cfg` with the following. Each section is annotated with what's new vs. unchanged.

```haproxy
# =============================================================================
# DX Docker-Compose HAProxy POC
# Enhances existing config with: Cookie Security, Session Tracking,
#                                  Stats Dashboard, Failover, Logging
# =============================================================================

# ------------------------------------------------------------------------------
# GLOBAL SETTINGS (unchanged, plus stats socket)
# ------------------------------------------------------------------------------
global
    maxconn 50000
    log stdout format raw local0 info
    nbthread 4
    # [NEW] Stats socket for admin access (useful for querying stick tables)
    stats socket /var/run/haproxy.sock mode 660 level admin

# ------------------------------------------------------------------------------
# DEFAULTS (enhanced with failover and custom logging)
# ------------------------------------------------------------------------------
defaults
    timeout connect 10s
    timeout client 1200s
    timeout server 1200s
    log global
    mode http
    option httplog
    # [NEW - FAILOVER] Re-dispatch to another server if current one is down
    option redispatch
    # [UNCHANGED] roundrobin is fine for 2 DX Core instances
    balance roundrobin
    # [NEW - LOGGING] Custom log format with source IP removed (privacy)
    log-format "[%tr] %ft %b/%s %TR/%Tw/%Tc/%Tr/%Ta %ST %B %CC %CS %tsc %ac/%fc/%bc/%sc/%rc %sq/%bq %hr %hs %{+Q}r"

# ------------------------------------------------------------------------------
# DNS RESOLVER (changed from parse-resolv-conf to explicit Docker DNS)
# ------------------------------------------------------------------------------
resolvers docker-dns
    nameserver dns 127.0.0.11:53
    resolve_retries 3
    timeout resolve 1s
    timeout retry 1s
    accepted_payload_size 8192
    hold valid 5s

# ------------------------------------------------------------------------------
# [NEW - SESSION TRACKING] Persist stick tables across HAProxy reloads
# ------------------------------------------------------------------------------
peers localPeer
    peer local 127.0.0.1:10000

# ------------------------------------------------------------------------------
# [NEW - STATS DASHBOARD] Visual verification of backends and sessions
# Access at http://localhost:8404/stats
# ------------------------------------------------------------------------------
frontend stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 10s

# ------------------------------------------------------------------------------
# [NEW - HEALTH PROBE] Returns 200 OK for container health checks
# Internal only — port 8888 is not exposed in dx.yaml
# ------------------------------------------------------------------------------
frontend probe
    no log
    bind *:8888
    http-request return status 200 content-type "text/plain" string "OK"

# ------------------------------------------------------------------------------
# FRONTEND: Main DX Traffic
# [UNCHANGED] Path routing + [NEW] User session tracking
# ------------------------------------------------------------------------------
frontend dx
    bind :8081

    # ------------------------------------------------------------------
    # [UNCHANGED] Path routing — same 4 routes as original
    # ------------------------------------------------------------------
    use_backend dam if { path -m reg ^/dx/(api|ui)/dam/ }
    use_backend content if { path_beg /dx/ui/content/ }
    use_backend image-processor if { path_beg /dx/api/image-processor/ }
    use_backend ring-api if { path_beg /dx/api/core/ }

    # ------------------------------------------------------------------
    # [NEW - USER SESSION TRACKING] Track per-user request rates
    # ------------------------------------------------------------------
    # Build a unique fingerprint per user: source IP + User-Agent + X-Forwarded-For
    stick-table type string len 180 size 1m expire 30m store http_req_rate(30m),gpc0 peers localPeer
    http-request set-header X-Concat --%[src]_%[req.fhdr(User-Agent)]_%[req.fhdr(X-Forwarded-For,-1)]--
    http-request track-sc0 req.fhdr(X-Concat)

    # ------------------------------------------------------------------
    # [UNCHANGED] Default: all unmatched traffic goes to Core
    # ------------------------------------------------------------------
    default_backend core-dx-home

# ------------------------------------------------------------------------------
# BACKEND: Core DX (2 instances: core + core2)
# [UNCHANGED] Load balancing + Sticky sessions
# [ENHANCED] Cookie security (httponly added)
# ------------------------------------------------------------------------------
backend core-dx-home
    # [NEW] Detect session-related cookies in backend responses
    acl has_jsession_cookie res.cook(JSESSIONID) -m found
    acl has_ltpa_cookie res.cook(LtpaToken2) -m found

    # [ENHANCED - COOKIE SECURITY] Added httponly to existing DXSRVID cookie
    # - insert: HAProxy creates the cookie (not the app)
    # - indirect: cookie is not passed to the backend server
    # - nocache: adds Cache-Control: no-cache to responses that set this cookie
    # - httponly: not accessible via JavaScript (NEW)
    cookie DXSRVID insert indirect nocache httponly

    # [UNCHANGED] 2 static Core servers
    server core1 dx-core:10039 check resolvers docker-dns init-addr none cookie core1
    server core2 dx-core-2:10039 check resolvers docker-dns init-addr none cookie core2

# ------------------------------------------------------------------------------
# BACKEND: Digital Asset Management (unchanged)
# ------------------------------------------------------------------------------
backend dam
    server dam dx-dam:3001 check resolvers docker-dns init-addr none

# ------------------------------------------------------------------------------
# BACKEND: Content Composer (unchanged)
# ------------------------------------------------------------------------------
backend content
    server content dx-cc:3000 check resolvers docker-dns init-addr none

# ------------------------------------------------------------------------------
# BACKEND: Image Processor (unchanged)
# ------------------------------------------------------------------------------
backend image-processor
    server image-processor dx-image-processor:8080 check resolvers docker-dns init-addr none

# ------------------------------------------------------------------------------
# BACKEND: Ring API (unchanged)
# ------------------------------------------------------------------------------
backend ring-api
    server ring-api dx-ringapi:3000 check resolvers docker-dns init-addr none
```

---

### 4.3 Summary of Changes from Original `haproxy.cfg`

| Area | Original | POC |
|---|---|---|
| Load balancing | `balance roundrobin` | `balance roundrobin` (unchanged, fine for 2 instances) |
| Failover | None | `option redispatch` **(new)** |
| Core backend | 2 static servers (`dx-core` + `dx-core-2`) | Same 2 static servers (unchanged) |
| Sticky sessions | `cookie DXSRVID insert indirect nocache` | `cookie DXSRVID insert indirect nocache httponly` **(added httponly)** |
| Session cookie detection | None | ACLs for `JSESSIONID` and `LtpaToken2` **(new)** |
| User session tracking | None | Stick table with `X-Concat` fingerprint **(new)** |
| Stick table persistence | None | `peers localPeer` **(new)** |
| Stats dashboard | None | Frontend on port 8404 **(new)** |
| Health probe | None | Frontend on port 8888, internal only **(new)** |
| Path routing | 4 routes | 4 routes (unchanged) |
| Log format | Default | Custom, IPs removed **(new)** |
| DNS resolver | `parse-resolv-conf` | Explicit Docker DNS `127.0.0.11:53` **(changed)** |
| Backend server names | Hardcoded container names | Hardcoded container names (unchanged) |

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
Expected: `dx-core` and `dx-core-2` containers running.

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

### 5.3 Verify Load Balancing & Stats Dashboard

Open the stats dashboard at **http://localhost:8404/stats** and confirm:
- `core-dx-home` backend shows **2 servers** (green = healthy)
- Both servers have non-zero session counts after sending traffic

```bash
for i in $(seq 1 10); do
  curl -s -o /dev/null -w "Request $i: %{http_code}\n" http://localhost/wps/portal
done
```

### 5.4 Verify Sticky Sessions & Cookie Security

1. Make an initial request and capture the response cookies:
```bash
curl -v -c cookies.txt http://localhost/wps/portal 2>&1 | grep -i "set-cookie"
```

2. Verify the `DXSRVID` cookie is present with `HttpOnly` attribute.

3. Make subsequent requests with the cookie and verify they go to the same server:
```bash
for i in $(seq 1 5); do
  curl -s -b cookies.txt -o /dev/null -w "Request $i: %{http_code}\n" http://localhost/wps/portal
done
```

4. In the stats dashboard, confirm that only **one** of the two core servers received all 5 requests.

### 5.5 Verify User Session Tracking

Query the stick table via the HAProxy socket:

```bash
docker exec dx-haproxy sh -c "echo 'show table dx' | socat stdio /var/run/haproxy.sock"
```

Expected output shows tracked entries with request rates:
```
# table: dx, type: string, size:1048576, used:1
0x... key=--172.18.0.1_curl/8.1.2_-- use=0 exp=1799230 ...  http_req_rate(30000)=5 gpc0=0
```

---

## 6. How Each Capability Maps to Config

| Capability | Config Directives | Where to Verify |
|---|---|---|
| **Cookie Security** | `httponly` added to `cookie DXSRVID` | `curl -v` → `Set-Cookie: DXSRVID=...; HttpOnly` |
| **User Session Tracking** | `stick-table`, `X-Concat` header, `track-sc0` | `show table dx` via socket → entries with `http_req_rate` |
| **Stats Dashboard** | `frontend stats` on port 8404 | Browser → `http://localhost:8404/stats` |
| **Failover** | `option redispatch` | Stop one core → traffic re-routes to the other |
| **Logging** | Custom `log-format` | `docker logs dx-haproxy` → no source IPs in logs |
| **Health Probe** | `frontend probe` on port 8888 | Internal only, not tested from host |

---

## 7. Known Limitations

1. **No SSL** — All traffic is HTTP. Production would use HTTPS with SSL termination at HAProxy.
2. **No `Secure`/`SameSite` on cookies** — These require HTTPS to be meaningful.
3. **Core replicas share no state** — DX Core is stateful (WebSphere). Two independent Core instances will have separate sessions. This POC demonstrates HAProxy's routing behavior, not DX Core clustering.
4. **Static server entries** — `core1` and `core2` are hardcoded. In production, `server-template` with `deploy.replicas` would enable dynamic scaling.
5. **No rate limiting enforcement** — The stick table tracks rates but no ACL rules deny/throttle based on them. This is infrastructure-in-place for future enforcement.
6. **Single-instance backends** — DAM, CC, Image Processor, Ring API are not scaled. Only Core has 2 instances.
