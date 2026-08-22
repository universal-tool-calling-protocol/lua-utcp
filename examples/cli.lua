package.path='./lua/?.lua;./lua/?/init.lua;'..package.path
local cli=require('utcp.transports.cli')
local command=os.getenv('UTCP_CLI_COMMAND') or 'printf'
local args={'hello-from-lua-utcp'}
local result,err=cli.new({}):call({command=command,args=args},{})
assert(result,err)
print('CLI result:',type(result)=='table' and require('utcp.json').encode(result) or result)
