-- session-tracker.lua
-- Custom APISIX plugin for user session tracking
-- Matches HAProxy stick table capabilities:
--   1. Composite fingerprint (IP + User-Agent + X-Forwarded-For)
--   2. Multiple data points (count, first_seen, last_seen)
--   3. Admin query endpoint (dump all tracked sessions)

local core = require("apisix.core")
local ngx = ngx
local ngx_time = ngx.time

local plugin_name = "session-tracker"

local shared_dict_name = "plugin-session-tracker"

local schema = {
    type = "object",
    properties = {
        -- max entries before oldest gets evicted
        max_entries = { type = "integer", default = 10000 },
        -- expiry in seconds (default 30 min, same as HAProxy)
        expire = { type = "integer", default = 1800 },
    },
}

local _M = {
    version = 0.1,
    priority = 1100,
    name = plugin_name,
    schema = schema,
}

-- Build composite fingerprint: IP + User-Agent + X-Forwarded-For
-- Equivalent to HAProxy's: --%[src]_%[req.fhdr(User-Agent)]_%[req.fhdr(X-Forwarded-For,-1)]--
local function build_fingerprint(ctx)
    local ip = ctx.var.remote_addr or "unknown"
    local ua = ctx.var.http_user_agent or "none"
    local xff = ctx.var.http_x_forwarded_for or "none"
    return "--" .. ip .. "_" .. ua .. "_" .. xff .. "--"
end

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

-- Access phase: track the request
function _M.access(conf, ctx)
    local dict = ngx.shared[shared_dict_name]
    if not dict then
        core.log.error("shared dict '", shared_dict_name, "' not found")
        return
    end

    local fingerprint = build_fingerprint(ctx)
    local expire = conf.expire or 1800
    local now = ngx_time()

    -- Store fingerprint in context for header_filter phase
    ctx.session_fingerprint = fingerprint

    -- Increment request count
    local count, err = dict:incr(fingerprint .. "::count", 1, 0, expire)
    if not count then
        core.log.error("failed to increment count: ", err)
        return
    end
    ctx.session_count = count

    -- Set first_seen (only if not already set)
    local first_seen = dict:get(fingerprint .. "::first_seen")
    if not first_seen then
        dict:set(fingerprint .. "::first_seen", now, expire)
        first_seen = now
    end
    ctx.session_first_seen = first_seen

    -- Update last_seen
    dict:set(fingerprint .. "::last_seen", now, expire)

    -- Store the fingerprint key itself for enumeration
    -- We use a separate "keys" namespace to track all active fingerprints
    dict:set("key::" .. fingerprint, now, expire)
end

-- Header filter phase: add tracking headers to response
function _M.header_filter(conf, ctx)
    if ctx.session_fingerprint then
        core.response.set_header(
            "X-Session-Fingerprint", ctx.session_fingerprint,
            "X-Session-Request-Count", tostring(ctx.session_count or 0),
            "X-Session-First-Seen", tostring(ctx.session_first_seen or 0)
        )
    end
end

-- API endpoint: dump all tracked sessions
-- Equivalent to HAProxy's "show table dx"
function _M.api()
    return {
        {
            methods = { "GET" },
            uri = "/apisix/plugin/session-tracker/dump",
            handler = function(conf)
                local dict = ngx.shared[shared_dict_name]
                if not dict then
                    return 500, { error = "shared dict not found" }
                end

                local keys = dict:get_keys(0)
                local sessions = {}

                for _, key in ipairs(keys) do
                    -- Only process fingerprint keys (prefixed with "key::")
                    if key:sub(1, 5) == "key::" then
                        local fingerprint = key:sub(6)
                        local count = dict:get(fingerprint .. "::count") or 0
                        local first_seen = dict:get(fingerprint .. "::first_seen") or 0
                        local last_seen = dict:get(fingerprint .. "::last_seen") or 0

                        sessions[#sessions + 1] = {
                            fingerprint = fingerprint,
                            request_count = count,
                            first_seen = first_seen,
                            last_seen = last_seen,
                        }
                    end
                end

                return 200, {
                    total = #sessions,
                    sessions = sessions,
                }
            end,
        },
    }
end

return _M
