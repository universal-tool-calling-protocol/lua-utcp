package.path='./lua/?.lua;./lua/?/init.lua;'..package.path
local utcp=require('utcp')
local c=utcp.new({})
c:add_manual({tools={{name='echo',description='HTTP echo',inputs={type='object'},tool_call_template={call_template_type='http',url=os.getenv('UTCP_HTTP_URL') or 'http://127.0.0.1:8080/echo',http_method='POST'}}}})
local result,err=c:call_tool('echo',{message='hello from lua-utcp'})
assert(result,err)
print('HTTP result:',require('utcp.json').encode(result))
