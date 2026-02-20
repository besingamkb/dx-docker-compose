#!/bin/sh
# Wait for APISIX to be ready
echo "Waiting for APISIX Admin API to be ready..."
until curl -s -o /dev/null http://localhost:9180/apisix/admin/routes -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1"; do
  echo "APISIX not ready yet, retrying in 3s..."
  sleep 3
done
echo "APISIX Admin API is ready!"

ADMIN="http://localhost:9180/apisix/admin"
KEY="X-API-KEY: edd1c9f034335f136f87ad84b625c8f1"

# ============================================================
# Upstream 1: DX Core (round robin for new requests)
# ============================================================
echo "Creating upstream: dx-core (round robin)..."
curl -s -X PUT "$ADMIN/upstreams/1" -H "$KEY" -H "Content-Type: application/json" -d '{
  "name": "dx-core-upstream-roundrobin",
  "type": "roundrobin",
  "nodes": {
    "dx-core:10039": 1,
    "dx-core-2:10039": 1
  },
  "timeout": {
    "connect": 10,
    "send": 1200,
    "read": 1200
  },
  "retries": 1,
  "retry_timeout": 10
}'
echo ""

# ============================================================
# Upstream 6: DX Core 1 only (sticky target)
# ============================================================
echo "Creating upstream: dx-core1 (sticky)..."
curl -s -X PUT "$ADMIN/upstreams/6" -H "$KEY" -H "Content-Type: application/json" -d '{
  "name": "dx-core1-sticky",
  "type": "roundrobin",
  "nodes": {
    "dx-core:10039": 1
  },
  "timeout": {
    "connect": 10,
    "send": 1200,
    "read": 1200
  }
}'
echo ""

# ============================================================
# Upstream 7: DX Core 2 only (sticky target)
# ============================================================
echo "Creating upstream: dx-core2 (sticky)..."
curl -s -X PUT "$ADMIN/upstreams/7" -H "$KEY" -H "Content-Type: application/json" -d '{
  "name": "dx-core2-sticky",
  "type": "roundrobin",
  "nodes": {
    "dx-core-2:10039": 1
  },
  "timeout": {
    "connect": 10,
    "send": 1200,
    "read": 1200
  }
}'
echo ""

# ============================================================
# Upstream 2: DAM
# ============================================================
echo "Creating upstream: dx-dam..."
curl -s -X PUT "$ADMIN/upstreams/2" -H "$KEY" -H "Content-Type: application/json" -d '{
  "name": "dx-dam-upstream",
  "type": "roundrobin",
  "nodes": {
    "dx-dam:3001": 1
  },
  "timeout": {
    "connect": 10,
    "send": 1200,
    "read": 1200
  }
}'
echo ""

# ============================================================
# Upstream 3: Content Composer
# ============================================================
echo "Creating upstream: dx-cc..."
curl -s -X PUT "$ADMIN/upstreams/3" -H "$KEY" -H "Content-Type: application/json" -d '{
  "name": "dx-cc-upstream",
  "type": "roundrobin",
  "nodes": {
    "dx-cc:3000": 1
  },
  "timeout": {
    "connect": 10,
    "send": 1200,
    "read": 1200
  }
}'
echo ""

# ============================================================
# Upstream 4: Image Processor
# ============================================================
echo "Creating upstream: dx-image-processor..."
curl -s -X PUT "$ADMIN/upstreams/4" -H "$KEY" -H "Content-Type: application/json" -d '{
  "name": "dx-image-processor-upstream",
  "type": "roundrobin",
  "nodes": {
    "dx-image-processor:8080": 1
  },
  "timeout": {
    "connect": 10,
    "send": 1200,
    "read": 1200
  }
}'
echo ""

# ============================================================
# Upstream 5: Ring API
# ============================================================
echo "Creating upstream: dx-ringapi..."
curl -s -X PUT "$ADMIN/upstreams/5" -H "$KEY" -H "Content-Type: application/json" -d '{
  "name": "dx-ringapi-upstream",
  "type": "roundrobin",
  "nodes": {
    "dx-ringapi:3000": 1
  },
  "timeout": {
    "connect": 10,
    "send": 1200,
    "read": 1200
  }
}'
echo ""

# ============================================================
# Route 1: DAM API + UI  /dx/(api|ui)/dam/
# ============================================================
echo "Creating route: DAM..."
curl -s -X PUT "$ADMIN/routes/1" -H "$KEY" -H "Content-Type: application/json" -d '{
  "name": "dam-route",
  "uri": "/dx/*/dam/*",
  "vars": [
    ["uri", "~~", "^/dx/(api|ui)/dam/"]
  ],
  "upstream_id": 2,
  "priority": 10
}'
echo ""

# ============================================================
# Route 2: Content Composer  /dx/ui/content/
# ============================================================
echo "Creating route: Content Composer..."
curl -s -X PUT "$ADMIN/routes/2" -H "$KEY" -H "Content-Type: application/json" -d '{
  "name": "content-composer-route",
  "uri": "/dx/ui/content/*",
  "upstream_id": 3,
  "priority": 10
}'
echo ""

# ============================================================
# Route 3: Image Processor  /dx/api/image-processor/
# ============================================================
echo "Creating route: Image Processor..."
curl -s -X PUT "$ADMIN/routes/3" -H "$KEY" -H "Content-Type: application/json" -d '{
  "name": "image-processor-route",
  "uri": "/dx/api/image-processor/*",
  "upstream_id": 4,
  "priority": 10
}'
echo ""

# ============================================================
# Route 4: Ring API  /dx/api/core/
# ============================================================
echo "Creating route: Ring API..."
curl -s -X PUT "$ADMIN/routes/4" -H "$KEY" -H "Content-Type: application/json" -d '{
  "name": "ring-api-route",
  "uri": "/dx/api/core/*",
  "upstream_id": 5,
  "priority": 10
}'
echo ""

# ============================================================
# Route 5: Sticky → DX Core 1 (when DXSRVID=core1 cookie present)
# ============================================================
echo "Creating route: DX Core sticky core1..."
curl -s -X PUT "$ADMIN/routes/5" -H "$KEY" -H "Content-Type: application/json" -d '{
  "name": "dx-core-sticky-core1",
  "uri": "/*",
  "upstream_id": 6,
  "priority": 2,
  "vars": [["cookie_DXSRVID", "==", "core1"]],
  "plugins": {
    "proxy-rewrite": {
      "host": "localhost:10039"
    },
    "serverless-post-function": {
      "phase": "header_filter",
      "functions": ["return function(conf, ctx) local loc = ngx.header[\"Location\"]; if loc then ngx.header[\"Location\"] = loc:gsub(\"localhost:10039\", \"localhost:90\") end end"]
    }
  }
}'
echo ""

# ============================================================
# Route 6: Sticky → DX Core 2 (when DXSRVID=core2 cookie present)
# ============================================================
echo "Creating route: DX Core sticky core2..."
curl -s -X PUT "$ADMIN/routes/6" -H "$KEY" -H "Content-Type: application/json" -d '{
  "name": "dx-core-sticky-core2",
  "uri": "/*",
  "upstream_id": 7,
  "priority": 2,
  "vars": [["cookie_DXSRVID", "==", "core2"]],
  "plugins": {
    "proxy-rewrite": {
      "host": "localhost:10039"
    },
    "serverless-post-function": {
      "phase": "header_filter",
      "functions": ["return function(conf, ctx) local loc = ngx.header[\"Location\"]; if loc then ngx.header[\"Location\"] = loc:gsub(\"localhost:10039\", \"localhost:90\") end end"]
    }
  }
}'
echo ""

# ============================================================
# Route 7: Default → DX Core round-robin (no cookie / new request)
# Sets DXSRVID cookie to pin subsequent requests.
# ============================================================
echo "Creating route: DX Core default round-robin..."
curl -s -X PUT "$ADMIN/routes/7" -H "$KEY" -H "Content-Type: application/json" -d '{
  "name": "dx-core-default-roundrobin",
  "uri": "/*",
  "upstream_id": 1,
  "priority": 1,
  "plugins": {
    "proxy-rewrite": {
      "host": "localhost:10039"
    },
    "serverless-post-function": {
      "phase": "header_filter",
      "functions": ["return function(conf, ctx) local loc = ngx.header[\"Location\"]; if loc then ngx.header[\"Location\"] = loc:gsub(\"localhost:10039\", \"localhost:90\") end; local upstream_addr = ngx.var.upstream_addr or \"\"; local server_id = \"core1\"; if upstream_addr:find(\"dx%-core%-2\") or upstream_addr:find(\"%.7:\") or upstream_addr:find(\"%.11:\") then server_id = \"core2\" end; ngx.header[\"Set-Cookie\"] = \"DXSRVID=\" .. server_id .. \"; Path=/; HttpOnly\" end"]
    }
  }
}'
echo ""

# ============================================================
# Global Rule: Session Tracking (applies to ALL routes)
# Equivalent to HAProxy's stick-table tracking
# Composite fingerprint: IP + User-Agent + X-Forwarded-For
# ============================================================
echo "Creating global rule: Session tracking..."
curl -s -X PUT "$ADMIN/global_rules/1" -H "$KEY" -H "Content-Type: application/json" -d '{
  "plugins": {
    "serverless-pre-function": {
      "phase": "access",
      "functions": ["return function(conf, ctx) local dict = ngx.shared[\"plugin-session-tracker\"]; if not dict then return end; local ip = ngx.var.remote_addr or \"unknown\"; local ua = ngx.var.http_user_agent or \"none\"; local xff = ngx.var.http_x_forwarded_for or \"none\"; local fp = \"--\" .. ip .. \"_\" .. ua .. \"_\" .. xff .. \"--\"; local now = ngx.time(); dict:incr(fp .. \"::count\", 1, 0, 1800); if not dict:get(fp .. \"::first_seen\") then dict:set(fp .. \"::first_seen\", now, 1800) end; dict:set(fp .. \"::last_seen\", now, 1800); dict:set(\"key::\" .. fp, now, 1800) end"]
    }
  }
}'
echo ""

# ============================================================
# Route 8: Session Tracker Dump (admin query endpoint)
# Equivalent to HAProxy's "show table dx" via socket
# ============================================================
echo "Creating route: Session tracker dump..."
curl -s -X PUT "$ADMIN/routes/8" -H "$KEY" -H "Content-Type: application/json" -d '{
  "name": "session-tracker-dump",
  "uri": "/session-tracker/dump",
  "upstream_id": 1,
  "priority": 20,
  "plugins": {
    "serverless-pre-function": {
      "phase": "access",
      "functions": ["return function(conf, ctx) local cjson = require(\"cjson\"); local dict = ngx.shared[\"plugin-session-tracker\"]; if not dict then ngx.header[\"Content-Type\"] = \"application/json\"; ngx.say(cjson.encode({error = \"shared dict not found\"})); ngx.exit(500); return end; local keys = dict:get_keys(0); local sessions = {}; for _, key in ipairs(keys) do if key:sub(1, 5) == \"key::\" then local fp = key:sub(6); sessions[#sessions + 1] = {fingerprint = fp, request_count = dict:get(fp .. \"::count\") or 0, first_seen = dict:get(fp .. \"::first_seen\") or 0, last_seen = dict:get(fp .. \"::last_seen\") or 0} end end; ngx.header[\"Content-Type\"] = \"application/json\"; ngx.say(cjson.encode({total = #sessions, sessions = sessions})); ngx.exit(200) end"]
    }
  }
}'
echo ""

echo "============================================"
echo "APISIX configuration complete!"
echo "============================================"
echo ""
echo "Routes configured:"
curl -s "$ADMIN/routes" -H "$KEY" | grep -o '"name":"[^"]*"' | sort
echo ""
echo "Upstreams configured:"
curl -s "$ADMIN/upstreams" -H "$KEY" | grep -o '"name":"[^"]*"' | sort
echo ""
echo "Global rules configured:"
curl -s "$ADMIN/global_rules" -H "$KEY" | grep -o '"id":"[^"]*"' | sort

