package.path='./lua/?.lua;./lua/?/init.lua;'..package.path
local text=require('utcp.transports.text')
local path=os.getenv('UTCP_TEXT_FILE') or 'examples/tool-result.json'
local result,err=text.new({}):call({path=path},{})
assert(result,err)
print('Text result:',require('utcp.json').encode(result))
