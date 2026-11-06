-- KEK — sérialisation compacte des tables Lua pour les messages d'addon.
-- Format : ^S chaîne, ^N nombre, ^B vrai, ^b faux, ^Z nil, ^T … ^t table.
-- Les caractères sensibles (contrôle, ^, ~, |) sont échappés en ~XX.
local _, ns = ...

local Ser = {}
ns.Ser = Ser

local format, byte, char, gsub, find, sub = string.format, string.byte, string.char, string.gsub, string.find, string.sub
local tonumber, type, pairs, concat, floor = tonumber, type, pairs, table.concat, math.floor

local function escape(s)
  return (gsub(s, "[%c%^~|\127]", function(c) return format("~%02X", byte(c)) end))
end

local function unescape(s)
  return (gsub(s, "~(%x%x)", function(h) return char(tonumber(h, 16)) end))
end

local function encodeValue(v, out, n)
  local t = type(v)
  if t == "string" then
    n = n + 1; out[n] = "^S" .. escape(v)
  elseif t == "number" then
    local s
    if v ~= v or v == math.huge or v == -math.huge then
      s = "0"
    elseif v == floor(v) then
      s = format("%.14g", v)   -- pas de %d : sous Windows il déborde au-delà de 2^31
    else
      s = format("%.10g", v)
    end
    n = n + 1; out[n] = "^N" .. s
  elseif t == "boolean" then
    n = n + 1; out[n] = v and "^B" or "^b"
  elseif t == "table" then
    n = n + 1; out[n] = "^T"
    for k, val in pairs(v) do
      local kt, vt = type(k), type(val)
      if (kt == "string" or kt == "number") and (vt == "string" or vt == "number" or vt == "boolean" or vt == "table") then
        n = encodeValue(k, out, n)
        n = encodeValue(val, out, n)
      end
    end
    n = n + 1; out[n] = "^t"
  else
    n = n + 1; out[n] = "^Z"
  end
  return n
end

function Ser.Encode(v)
  local out = {}
  encodeValue(v, out, 0)
  return concat(out)
end

function Ser.Decode(s)
  if type(s) ~= "string" or s == "" then return nil end
  local pos, len = 1, #s

  local function token()
    if pos > len then error("eof", 0) end
    if sub(s, pos, pos) ~= "^" then error("bad token", 0) end
    local tag = sub(s, pos + 1, pos + 1)
    local stop = find(s, "^", pos + 2, true)
    local data
    if stop then
      data = sub(s, pos + 2, stop - 1)
      pos = stop
    else
      data = sub(s, pos + 2)
      pos = len + 1
    end
    return tag, data
  end

  local read
  read = function(tag, data, depth)
    if tag == "S" then return unescape(data)
    elseif tag == "N" then return tonumber(data) or 0
    elseif tag == "B" then return true
    elseif tag == "b" then return false
    elseif tag == "Z" then return nil
    elseif tag == "T" then
      if depth > 20 then error("too deep", 0) end
      local t = {}
      while true do
        local kt, kd = token()
        if kt == "t" then return t end
        local k = read(kt, kd, depth + 1)
        local vt, vd = token()
        local v = read(vt, vd, depth + 1)
        if k ~= nil then t[k] = v end
      end
    end
    error("unknown tag", 0)
  end

  local ok, result = pcall(function()
    local tag, data = token()
    return read(tag, data, 0)
  end)
  if ok then return result end
  return nil
end
