package.path = './lua/?.lua;./lua/?/init.lua;'..package.path

local fake_http = { response = nil, calls = 0, TIMEOUT = nil }

local function install_fake_http(response)
  fake_http.response = response
  fake_http.calls = 0
  package.loaded['socket.http'] = fake_http
  package.loaded['ltn12'] = {
    source = { string = function(body) return function() return body end end },
    sink = { table = function(target)
      return function(chunk)
        if chunk then target[#target + 1] = chunk end
        return 1
      end
    end },
  }
end

function fake_http.request(req)
  fake_http.calls = fake_http.calls + 1
  assert(req.sink, 'request must provide a sink')
  local r = fake_http.response
  if r.raise then error(r.raise) end
  if r.body then req.sink(r.body); req.sink(nil) end
  return r.ok, r.code, r.headers or {}, r.status
end

install_fake_http({ok = true, code = 200, body = '{"ok":true}', headers = {['content-type'] = 'application/json'}, status = '200 OK'})
local Http = require('utcp.transports.http')
local SSE = require('utcp.transports.sse')
local Streamable = require('utcp.transports.streamable')

local http = Http.new({timeout = 2})
local result, err, headers, raw = http:request('POST', 'http://test.local/tool', {value = 1}, {})
assert(result.ok == true)
assert(err == nil)
assert(headers['content-type'] == 'application/json')
assert(raw == '{"ok":true}')
assert(fake_http.TIMEOUT == nil, 'HTTP timeout must be restored after request')

install_fake_http({ok = false, code = 'connection refused'})
local failed, failure = http:request('GET', 'http://test.local/down', nil, {})
assert(failed == nil)
assert(failure == 'connection refused')

install_fake_http({ok = true, code = 503, status = '503 Service Unavailable'})
local unavailable, unavailable_err = http:request('GET', 'http://test.local/down', nil, {})
assert(unavailable == nil)
assert(unavailable_err:match('^HTTP 503'))

install_fake_http({ok = true, code = 200, body = 'not-json', headers = {['content-type'] = 'text/plain'}})
local text, text_err = http:request('GET', 'http://test.local/text', nil, {})
assert(text == 'not-json')
assert(text_err == nil)

install_fake_http({ok = true, code = 200, body = 'false', headers = {['content-type'] = 'application/json'}})
local boolean = http:request('GET', 'http://test.local/boolean', nil, {})
assert(boolean == false, 'JSON false must not fall back to the raw response text')

install_fake_http({ok = true, code = 200, body = 'data: {"value":42}\n\nevent: done\ndata: ok\n\n', headers = {['content-type'] = 'text/event-stream'}})
local events = {}
local sse = SSE.new({timeout = 3})
local sse_ok, sse_err = sse:listen('http://test.local/events', function(event)
  events[#events + 1] = event
end)
assert(sse_ok == true)
assert(sse_err == nil)
assert(#events == 2)
assert(events[1].event == 'message')
assert(events[1].data.value == 42)
assert(events[2].event == 'done')
assert(events[2].data == 'ok')
assert(fake_http.TIMEOUT == nil, 'SSE timeout must be restored after request')

install_fake_http({ok = true, code = 502, status = '502 Bad Gateway'})
local sse_failed, sse_failure = sse:listen('http://test.local/events', function() end)
assert(sse_failed == nil)
assert(sse_failure:match('^SSE HTTP error:'))

install_fake_http({ok = true, code = 200, body = 'data: {"value":7}\n\n', headers = {['content-type'] = 'text/event-stream'}})
local streamed = {}
local streamable = Streamable.new({timeout = 4})
local stream_result, stream_err = streamable:call({url = 'http://test.local/stream'}, {}, function(event)
  streamed[#streamed + 1] = event
end)
assert(stream_result == nil)
assert(stream_err == nil)
assert(#streamed == 1)
assert(streamed[1].data.value == 7)
assert(fake_http.TIMEOUT == nil, 'Streamable timeout must be restored after request')

install_fake_http({raise = 'socket timeout'})
local raised, raised_err = http:request('GET', 'http://test.local/timeout', nil, {})
assert(raised == nil)
assert(raised_err == 'socket timeout')
assert(fake_http.TIMEOUT == nil, 'HTTP timeout must be restored after raised request')

print('transport reliability tests: ok')
