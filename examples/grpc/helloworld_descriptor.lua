-- FileDescriptorSet for helloworld.proto, encoded as text so the example does
-- not require protoc at runtime.
local encoded = [[
Cv4BChBoZWxsb3dvcmxkLnByb3RvEgpoZWxsb3dvcmxkIiIKDEhlbGxvUmVxdWVzdBISCgRuYW1lGAEgASgJUgRuYW1lIiYKCkhlbGxvUmVwbHkSGAoHbWVzc2FnZRgBIAEoCVIHbWVzc2FnZTKJAQoHR3JlZXRlchI8CghTYXlIZWxsbxIYLmhlbGxvd29ybGQuSGVsbG9SZXF1ZXN0GhYuaGVsbG93b3JsZC5IZWxsb1JlcGx5EkAKCldhdGNoSGVsbG8SGC5oZWxsb3dvcmxkLkhlbGxvUmVxdWVzdBoWLmhlbGxvd29ybGQuSGVsbG9SZXBseTABYgZwcm90bzM=
]]

local alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function value(character)
  if character == '=' then return 0 end
  return assert(alphabet:find(character, 1, true), 'invalid base64 descriptor') - 1
end

return (encoded:gsub('%s', ''):gsub('....', function(group)
  local a, b = value(group:sub(1, 1)), value(group:sub(2, 2))
  local c, d = value(group:sub(3, 3)), value(group:sub(4, 4))
  local number = a * 262144 + b * 4096 + c * 64 + d
  local first = math.floor(number / 65536) % 256
  local second = math.floor(number / 256) % 256
  local third = number % 256
  if group:sub(3, 3) == '=' then return string.char(first) end
  if group:sub(4, 4) == '=' then return string.char(first, second) end
  return string.char(first, second, third)
end))
