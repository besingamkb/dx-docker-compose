# HAProxy POC Commands

All commands use HAProxy on port `80`. Make sure services are running:
```bash
source set.sh && docker-compose -f dx.yaml up -d
```

---

## 1. Load Balancer

Send 10 requests and verify via stats dashboard:

```bash
for i in $(seq 1 10); do
  curl -s -o /dev/null -w "Request $i: %{http_code}\n" http://localhost/wps/portal
done
```

Then open **http://localhost:8404/stats** in a browser. Check `core-dx-home` backend — both servers should show session counts.

**What to look for:** All requests return `302` (both cores healthy). Stats dashboard shows 2 green servers with distributed sessions.

---

## 2. Path Routing

Each request hits a different backend:

```bash
curl -s -o /dev/null -w "Core:    %{http_code}\n" http://localhost/wps/portal
curl -s -o /dev/null -w "DAM:     %{http_code}\n" http://localhost/dx/api/dam/v1/collections
curl -s -o /dev/null -w "CC:      %{http_code}\n" http://localhost/dx/ui/content/
curl -s -o /dev/null -w "ImgProc: %{http_code}\n" http://localhost/dx/api/image-processor/
curl -s -o /dev/null -w "RingAPI: %{http_code}\n" http://localhost/dx/api/core/
```

**What to look for:** No `502`/`503` — any response (200, 302, 404) means routing worked and the request reached the correct backend.

---

## 3. Cookie Management

First request sets the `DXSRVID` cookie with `HttpOnly`:

```bash
curl -v -c cookies.txt http://localhost/wps/portal 2>&1 | grep -i "set-cookie"
```

**What to look for:** `Set-Cookie: DXSRVID=core1; HttpOnly`

Show the saved cookie:
```bash
cat cookies.txt
```

**What to look for:** `#HttpOnly_` prefix and value `core1` or `core2`.

---

## 4. Sticky Sessions

All requests with the cookie go to the **same** core:

```bash
# Send 5 requests with the cookie from step 3
for i in $(seq 1 5); do
  curl -s -b cookies.txt -o /dev/null -w "Request $i: %{http_code}\n" http://localhost/wps/portal
done
```

Then check **http://localhost:8404/stats** — only one of the two core servers should have received all 5 requests.

**What to look for:** All 5 return `302` — pinned to the same core matching the `DXSRVID` cookie value.

---

## 5. User Session Tracking

Query the stick table via HAProxy TCP socket:

```bash
echo "show table dx" | nc localhost 9999
```

**What to look for:**
```
# table: dx, type: string, size:1048576, used:1
0x... key=--172.18.0.1_curl/8.1.2_-- use=0 exp=... http_req_rate(30000)=5 gpc0=0
```

The `http_req_rate` value shows how many requests that user fingerprint has made in the tracking window.

Send more requests and check again to see the rate increase:
```bash
for i in $(seq 1 5); do
  curl -s -o /dev/null http://localhost/wps/portal
done
echo "show table dx" | nc localhost 9999
```

---

