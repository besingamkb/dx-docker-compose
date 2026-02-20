# APISIX POC Demo Commands

All commands use APISIX on port `90`. Make sure services are running and routes are configured:
```bash
source set.sh && docker-compose -f dx.yaml up -d
./apisix_conf/setup_routes.sh
```

---

## 1. Load Balancer

Send 10 requests and watch the count increase in Prometheus:

```bash
# Before
curl -s http://localhost:9091/apisix/prometheus/metrics | grep "apisix_http_requests_total"

# Send 10 requests
for i in $(seq 1 10); do
  curl -s -o /dev/null -w "Request $i: %{http_code}\n" http://localhost:90/wps/portal
done

# After — count should increase by ~10
curl -s http://localhost:9091/apisix/prometheus/metrics | grep "apisix_http_requests_total"
```

**What to look for:** All requests return `302` (both cores healthy). Prometheus total increases.

---

## 2. Path Routing

Each request hits a different backend:

```bash
curl -s -o /dev/null -w "Core:    %{http_code}\n" http://localhost:90/wps/portal
curl -s -o /dev/null -w "DAM:     %{http_code}\n" http://localhost:90/dx/api/dam/v1/collections
curl -s -o /dev/null -w "CC:      %{http_code}\n" http://localhost:90/dx/ui/content/
curl -s -o /dev/null -w "ImgProc: %{http_code}\n" http://localhost:90/dx/api/image-processor/
curl -s -o /dev/null -w "RingAPI: %{http_code}\n" http://localhost:90/dx/api/core/
```

**What to look for:** No `502`/`503` — any response (200, 302, 404) means routing worked and the request reached the correct backend.

---

## 3. Cookie Management

First request sets the `DXSRVID` cookie with `HttpOnly`:

```bash
curl -v -c cookies.txt http://localhost:90/wps/portal 2>&1 | grep -i "set-cookie"
```

**What to look for:** `Set-Cookie: DXSRVID=core1; Path=/; HttpOnly`

Show the saved cookie:
```bash
cat cookies.txt
```

**What to look for:** `#HttpOnly_` prefix (curl marks httponly cookies this way) and value `core1` or `core2`.

---

## 4. Sticky Sessions

All requests with the cookie go to the **same** core:

```bash
# Send 5 requests with the cookie from step 3
for i in $(seq 1 5); do
  curl -s -b cookies.txt -o /dev/null -w "Request $i: %{http_code}\n" http://localhost:90/wps/portal
done
```

**What to look for:** All 5 return `302` — pinned to the same core (the one matching the `DXSRVID` cookie value).

---

## 5. User Session Tracking

Send requests, then dump all tracked sessions (equivalent to HAProxy's `show table dx`):

```bash
# Send some requests
for i in $(seq 1 5); do curl -s -o /dev/null http://localhost:90/wps/portal; done

# Dump all tracked sessions
curl -s http://localhost:90/session-tracker/dump | python3 -m json.tool
```

**What to look for:**
```json
{
    "total": 1,
    "sessions": [
        {
            "fingerprint": "--192.168.65.1_curl/8.7.1_none--",
            "request_count": 6,
            "first_seen": 1771587290,
            "last_seen": 1771587315
        }
    ]
}
```

- `fingerprint` — Composite key: IP + User-Agent + X-Forwarded-For (same as HAProxy)
- `request_count` — Total requests from this fingerprint
- `first_seen` / `last_seen` — Timestamps of first and most recent request

Send more requests and dump again to see `request_count` increase.
