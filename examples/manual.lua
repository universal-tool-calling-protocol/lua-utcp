package.path = './lua/?.lua;./lua/?/init.lua;'..package.path
local utcp=require('utcp')
local client=utcp.new({})
client:add_manual({manual_version='1.0',utcp_version='1.0',tools={
 {name='echo',description='Echo a message',inputs={type='object',properties={message={type='string'}}},tool_call_template={call_template_type='http',url='http://127.0.0.1:8080/echo',http_method='POST'}}
}})
print('registered tools:', #client:list_tools())
for _,tool in ipairs(client:list_tools()) do print(tool.name, tool.description) end
