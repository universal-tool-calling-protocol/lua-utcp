package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local json = require("utcp.json")
local mcp = require("utcp.transports.mcp")

local t = mcp.new({
    url = os.getenv("UTCP_MCP_URL") or "http://127.0.0.1:8093/mcp",
})

local initialized, err = t:initialize()
assert(initialized, err)
print("MCP initialized:", json.encode(initialized))

-- Discover tools using the canonical transport API.
local tools, err = t:list_tools()
assert(tools, err)
print("MCP tools:", json.encode(tools))

local name = os.getenv("UTCP_MCP_TOOL") or "echo"
local result, call_err = t:call_tool(name, { message = "hello from lua-utcp" })
assert(result, call_err)
print("MCP result:", json.encode(result))
