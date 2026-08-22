local json = require("utcp.json")
local http = require("utcp.transports.http")

local M = {}
local T = {}
T.__index = T

function T.new(cfg)
    cfg = cfg or {}

    local headers = {
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json, text/event-stream",
    }
    for k, v in pairs(cfg.headers or {}) do
        headers[k] = v
    end

    return setmetatable({
        url = assert(cfg.url, "MCP url is required"),
        headers = headers,
        timeout = cfg.timeout,
        _id = 0,
        _session_id = nil,
    }, T)
end

function T:request(method, params)
    self._id = self._id + 1
    local payload = {
        jsonrpc = "2.0",
        id = self._id,
        method = method,
        params = params or {},
    }

    -- Echo back the session id issued by the server during initialize.
    if self._session_id then
        self.headers["Mcp-Session-Id"] = self._session_id
    end

    local result, err, resp_headers = http.new({
        url = self.url,
        headers = self.headers,
        timeout = self.timeout,
    }):request("POST", self.url, payload, self.headers)

    if err then
        return nil, err
    end

    if resp_headers then
        local sid = resp_headers["mcp-session-id"] or resp_headers["Mcp-Session-Id"]
        if sid then
            self._session_id = sid
        end
    end

    if result and result.error then
        return nil, result.error.message or "MCP error"
    end
    return result and result.result or result
end

function T:initialize()
    local result, err = self:request("initialize", {
        protocolVersion = "2025-03-26",
        capabilities = {},
        clientInfo = { name = "lua-utcp", version = "1.0.0" },
    })
    if not result then
        return nil, err
    end

    -- Per MCP spec, client must send "notifications/initialized" after
    -- a successful initialize before making further requests.
    self:request("notifications/initialized", {})

    return result
end

function T:list_tools()
    return self:request("tools/list", {})
end

-- Alias used by clients that prefer MCP naming.
function T:tools_list()
    return self:list_tools()
end

function T:call_tool(name, args)
    return self:request("tools/call", {
        name = name,
        arguments = args or {},
    })
end

function T:tools_call(name, args)
    return self:call_tool(name, args)
end

function M.new(cfg)
    return T.new(cfg)
end

M.Transport = T
return M
