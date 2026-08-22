package.path = './lua/?.lua;./lua/?/init.lua;'..package.path
local utcp = require('utcp')
assert(utcp.json.available(), 'install lua-cjson or dkjson to run tests')
local client = utcp.new({})
client:add_manual({manual_version='1.0',utcp_version='1.0',tools={
  {name='echo',description='Echo',tags={'test'},inputs={type='object'},tool_call_template={call_template_type='http',url='http://127.0.0.1:1/echo',http_method='POST'}}
}})
assert(#client:list_tools()==1)
assert(client:find_tool('echo'))
assert(#client:search_tools('echo')==1)
assert(#client:search_tools('',{'test'})==1)
assert(client:find_tool('missing') == nil)
local s = assert(utcp.json.encode({hello='world'})); local v = assert(utcp.json.decode(s)); assert(v.hello=='world')
print('lua-utcp core tests: ok')
