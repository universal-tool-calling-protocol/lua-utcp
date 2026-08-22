package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

local utcp = require('utcp.client')
local json = require('utcp.json')

local url = os.getenv('UTCP_GRAPHQL_URL') or 'http://127.0.0.1:8092/graphql'

local client = utcp.new({
    providers = {
        {
            name = 'graphql',
            transport = 'graphql',
            url = url,
            tools = {
                {
                    name = 'add',
                    description = 'Add two numbers',
                    inputs = {
                        type = 'object',
                        properties = {
                            a = {type = 'number'},
                            b = {type = 'number'},
                        },
                        required = {'a', 'b'},
                    },
                    tool_call_template = {
                        call_template_type = 'graphql',
                        query = 'query($a: Int!, $b: Int!) { add(a: $a, b: $b) }',
                    },
                },
            },
        },
    },
})

local result, err = client:call_tool('graphql.add', {
    a = 7,
    b = 5,
})

assert(result ~= nil, err or 'GraphQL tool call failed')

print('GraphQL result:', json.encode(result))