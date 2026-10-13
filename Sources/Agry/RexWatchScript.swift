/// Lua run by `rex do --all`. It hears every Rex session (including ones created
/// later) from one process, snapshots existing status records at start, and
/// prints events as JSON lines in the same envelope `rex events --json` uses.
let rexWatchScript = #"""
local TERMINAL = "com.superlogical.terminal"
local escapes = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

local function enc(v)
  local t = type(v)
  if t == "string" then
    return '"' .. (v:gsub('[%c"\\]', function(c) return escapes[c] or string.format("\\u%04x", c:byte()) end)) .. '"'
  elseif t == "number" then
    return string.format("%.14g", v)
  elseif t == "boolean" then
    return tostring(v)
  elseif t == "table" then
    local parts = {}
    if #v > 0 then
      for _, item in ipairs(v) do parts[#parts + 1] = enc(item) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    for k, item in pairs(v) do parts[#parts + 1] = enc(tostring(k)) .. ":" .. enc(item) end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "null"
end

local function line(s)
  io.stdout:write(s, "\n")
  io.stdout:flush()
end

local function session_event(session_id, event_json)
  line('{"type":"session_event","payload":{"session_id":' .. enc(session_id) .. ',"event":' .. event_json .. '}}')
end

local function block_event(session_id, block_id, name, payload_json)
  session_event(session_id, '{"type":"block_event","payload":{"block_id":' .. enc(block_id)
    .. ',"creator_name":"' .. TERMINAL .. '","name":' .. enc(name) .. ',"payload":' .. payload_json .. '}}')
end

local function status_changed(session_id, block_id, id, record)
  block_event(session_id, block_id, "program_status_changed", '{"id":' .. enc(id or "") .. ',"record":' .. enc(record) .. '}')
end

rex.on("terminal.program_status_changed", function(ctx, ev)
  status_changed(ev.session_id, ev.block_id, ev.id, ev.record)
end)

rex.on("terminal.program_status_removed", function(ctx, ev)
  local ids = {}
  for _, id in ipairs(ev.ids or {}) do ids[#ids + 1] = enc(id) end
  block_event(ev.session_id, ev.block_id, "program_status_removed", '{"ids":[' .. table.concat(ids, ",") .. ']}')
end)

rex.on("block_closed", function(ctx, ev)
  session_event(ev.session_id, '{"type":"block_closed","payload":{"block_id":' .. enc(ev.block_id) .. '}}')
end)

rex.on("session_destroyed", function(ctx, ev)
  line('{"type":"session_destroyed","payload":{"session_id":' .. enc(ev.session_id) .. '}}')
end)

-- Under --all, the script body runs before Rex attaches it to any session,
-- so attach explicitly to read each session's blocks.
local list = rex.call("session.list") or {}
for _, s in ipairs(list.sessions or {}) do
  rex.session.attach({ session_id = s.session_id })
  local blocks = rex.call("session.list_blocks", { session_id = s.session_id }) or {}
  for _, b in ipairs(blocks.blocks or {}) do
    if b.creator_name == TERMINAL then
      local result = rex.call("block.method", { session_id = s.session_id, block_id = b.block_id, method = "program_status" }) or {}
      for _, record in ipairs(result.records or {}) do
        status_changed(s.session_id, b.block_id, record.id, record)
      end
    end
  end
end
line('{"type":"agry_ready"}')
"""#
