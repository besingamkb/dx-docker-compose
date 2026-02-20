# PRD-POC Review Notes — False/Inaccurate Claims

**PRD File:** `PRD-POC-DX-docker-compose-ha-proxy.md`
**Date:** February 20, 2026

---

## #1 — Load Balancing Algorithm ✅ RESOLVED

**PRD says:** "None (implicit `roundrobin`)"
**Reality:** Original `haproxy.cfg` explicitly declares `balance roundrobin` (line 41).
**Decision:** `roundrobin` is fine for this POC with only 2 DX Core instances. `leastconn` becomes relevant at 3+ servers.
**PRD updated:** Yes — corrected comparison table and added inline comment.

---

## #2 — Sticky Sessions: "None" ✅ RESOLVED

**PRD says (Section 4.3):** Original has no sticky sessions.
**Reality:** Original already has cookie-based sticky sessions:
```haproxy
cookie DXSRVID insert indirect nocache
server core1 dx-core:10039 ... cookie core1
server core2 dx-core-2:10039 ... cookie core2
```
The PRD frames sticky sessions as a brand-new capability, when it's actually an **upgrade** from static (`DXSRVID`) to dynamic (`DxSessionAffinity` with `httponly` + `dynamic`).
**Decision:** POC config is fine and is an improvement. PRD table corrected to reflect the original already has sticky sessions.
**PRD updated:** Yes — corrected comparison table.

---

## #3 — Core Backend: "Single static server" ✅ RESOLVED

**PRD says (Section 4.3):** Original has "Single static `server core dx-core:10039`"
**Reality:** Original already has **2 static server entries**:
```haproxy
server core1 dx-core:10039 ...
server core2 dx-core-2:10039 ...
```
And `dx.yaml` defines two separate services: `core` (container `dx-core`) and `core2` (container `dx-core-2`).
**Decision:** Keep the 2 hardcoded servers (`core` + `core2`) for this POC. No need for `server-template` or `deploy.replicas`.
**PRD updated:** Yes — corrected comparison table.

---

## #4 — Route Count: "4 routes → 6 routes" ✅ RESOLVED

**PRD says (Section 4.3):** Original has 4 routes, POC has 6.
**Reality:** Original has 4 routes (correct), but POC has **5** `use_backend` rules, not 6:
1. `^/dx/(api|ui)/dam/` → dam
2. `/dx/ui/picker/` → dam
3. `/dx/ui/content/` → content
4. `/dx/api/image-processor/` → image-processor
5. `/dx/api/core/` → ring-api

**Decision:** Keep original 4 routes unchanged. POC focuses on Core backend capabilities, no need to add the picker route.
**PRD updated:** Yes — corrected comparison table, commented out picker route in config.

---

## #5 — Volume Mount Path Discrepancy ✅ RESOLVED

**PRD proposes (Section 4.1):**
```yaml
- ./volumes/core/wp_profile/logs:/opt/HCL/wp_profile/logs
- ./volumes/core/cw_profile/logs:/opt/HCL/AppServer/profiles/cw_profile/logs
```
**Actual `dx.yaml`:**
```yaml
- ./volumes/core/wp_profile:/opt/HCL/wp_profile
```
PRD mounts only the **logs subdirectory**; the actual config mounts the **entire `wp_profile`**. Following the PRD literally would lose all non-log `wp_profile` data.
**Decision:** Keep original volumes unchanged. The PRD's volume changes were designed for the `deploy.replicas` approach, which we're not using.
**PRD updated:** Yes — added note in Section 4.1 that volumes remain unchanged.

---

## #6 — `core2` Service Not Mentioned for Removal ✅ RESOLVED

**PRD says (Section 4.1):** Remove `container_name` from `core`, add `deploy.replicas: 2`.
**Reality:** `dx.yaml` has a **separate `core2` service** (lines 34–49) with its own container name, ports, and volume path (`./volumes/core2/wp_profile`). The PRD never mentions that `core2` must be **removed** when switching to the replicas approach. Without removing it, you'd end up with 3 core instances.
**Decision:** Resolved by #3 — keeping the 2-service approach (`core` + `core2`), so `core2` stays. No removal needed.
**PRD updated:** N/A — already covered by #3 note in Section 4.1.

---

## #7 — Health Probe Port 8888 Not Exposed ✅ RESOLVED

**PRD proposes:** Health probe frontend on port `8888` in `haproxy.cfg`.
**PRD's proposed `dx.yaml`:** Only exposes `80:8081` and `8404:8404`. Port `8888` is not mapped.
**Impact:** Verification step `curl -s http://localhost:8888/` would fail from the host.
**Decision:** Keep the probe in `haproxy.cfg` (doesn't hurt anything) but don't expose port 8888 in `dx.yaml`. Not needed for a docker-compose POC — the stats dashboard (port 8404) is more useful for debugging.
**PRD updated:** Yes — added notes to health probe config and comparison table.
