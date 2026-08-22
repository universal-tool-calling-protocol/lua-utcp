package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local mcp = require("utcp.transports.mcp")
local t = mcp.new({ url = "http://127.0.0.1:8093/mcp" })

assert(type(t.initialize) == "function")
assert(type(t.request) == "function")
assert(type(t.list_tools) == "function")
assert(type(t.tools_list) == "function")
assert(type(t.call_tool) == "function")
assert(type(t.tools_call) == "function")

print("test_mcp: OK")
