local Client=require('utcp.client')
local M={Client=Client, Registry=require('utcp.registry'), errors=require('utcp.errors'), json=require('utcp.json'), transports=require('utcp.transports'), codemode=require('utcp.codemode'), provider=require('utcp.provider'), auth=require('utcp.auth'), guard=require('utcp.guard'), guards=require('utcp.guards')}
function M.new(cfg) return Client.new(cfg) end
function M.load_provider(path) return M.provider.load(path) end
return M
