-- party_mode.lua
-- VLC extension for offline timestamped comments with colored overlays

local json = require("dkjson") -- VLC ships with dkjson for JSON

local dialog = nil
local username = nil
local usercolor = nil
local reaction_file_path = nil
local reactions = { comments = {} }
local last_shown_index = 0
local overlay_text_id = nil

-- Generate random hex color
local function random_color()
  local function to_hex(n)
    local hex = string.format("%x", n)
    if #hex == 1 then hex = "0" .. hex end
    return hex
  end
  return "#" .. to_hex(math.random(0,255)) .. to_hex(math.random(0,255)) .. to_hex(math.random(0,255))
end

-- Pseudo hash: filename + filesize string
local function get_pseudo_hash()
  local input_item = vlc.input.item()
  if not input_item then return nil end
  local uri = input_item:uri()
  if not uri then return nil end
  local path = vlc.strings.decode_uri(uri)
  if path:sub(1,7) == "file://" then
    path = path:sub(8)
  end

  local file = io.open(path, "rb")
  if not file then return nil end
  file:seek("set", 0)
  local size = file:seek("end")
  file:close()

  local filename = path:match("^.+[/\\](.+)$") or path
  return filename .. "_" .. tostring(size)
end

-- Load reactions JSON
local function load_reactions()
  local file = io.open(reaction_file_path, "r")
  if not file then
    reactions = { comments = {} }
    return
  end
  local content = file:read("*all")
  file:close()
  local obj, pos, err = json.decode(content, 1, nil)
  if err then
    vlc.msg.err("Error parsing reactions JSON: " .. err)
    reactions = { comments = {} }
  else
    reactions = obj
  end
end

-- Save reactions JSON
local function save_reactions()
  local file = io.open(reaction_file_path, "w+")
  if not file then
    vlc.msg.err("Cannot write reactions file!")
    return
  end
  local content = json.encode(reactions, { indent = true })
  file:write(content)
  file:close()
end

-- Show overlay comment
local function show_comment(comment)
  if overlay_text_id then
    vlc.osd.message("", nil, overlay_text_id) -- clear previous overlay
  end
  local msg = string.format("[%s] %s", comment.user, comment.text)
  local color = comment.color or "#FFFFFF"
  local r = tonumber(color:sub(2,3),16) or 255
  local g = tonumber(color:sub(4,5),16) or 255
  local b = tonumber(color:sub(6,7),16) or 255
  local rgba = string.format("%02x%02x%02xFF", r, g, b)
  overlay_text_id = vlc.osd.message(msg, vlc.osd.channel_register(), "bottom-left", 100, 50, rgba)
end

-- Find comment to show at current time (±1s)
local function find_comment_at(time_sec)
  for i = last_shown_index + 1, #reactions.comments do
    local c = reactions.comments[i]
    if c.timestamp >= time_sec - 1 and c.timestamp <= time_sec + 1 then
      last_shown_index = i
      return c
    elseif c.timestamp > time_sec + 1 then
      break
    end
  end
  return nil
end

-- Add Comment dialog callback
local function add_comment()
  local time_us = vlc.var.get(vlc.object.input(), "time")
  if not time_us then
    vlc.msg.err("No video playing")
    return
  end
  local time_sec = time_us

  local d = vlc.dialog("Add Comment at " .. string.format("%.1f", time_sec) .. "s")
  local input_box = d:add_text_input("", 1, 1, 3, 1)

  d:add_button("Save", function()
    local txt = input_box:get_text()
    if txt ~= "" then
      local comment = {
        timestamp = math.floor(time_sec),
        user = username,
        text = txt,
        color = usercolor
      }
      table.insert(reactions.comments, comment)
      table.sort(reactions.comments, function(a,b) return a.timestamp < b.timestamp end)
      save_reactions()
      d:delete()
      vlc.msg.info("Comment saved!")
    end
  end, 1, 2, 1, 1)

  d:add_button("Cancel", function() d:delete() end, 2, 2, 1, 1)
  d:show()
end

-- Build main UI dialog
local function build_ui()
  if dialog then
    dialog:delete()
  end
  dialog = vlc.dialog("Party Mode")
  dialog:add_label("Username: " .. username, 1, 1, 2, 1)
  dialog:add_button("Add Comment", add_comment, 1, 2, 2, 1)
end

-- Ask for username dialog
local function ask_username()
  local d = vlc.dialog("Enter your username")
  local name_input = d:add_text_input("", 1, 1, 2, 1)
  d:add_button("OK", function()
    local val = name_input:get_text()
    if val ~= "" then
      username = val
      usercolor = random_color()
      vlc.config.set("party_mode_username", username)
      vlc.config.set("party_mode_usercolor", usercolor)
      d:delete()
      build_ui()
    else
      vlc.msg.info("Username can't be empty")
    end
  end, 1, 2, 1, 1)
  d:add_button("Cancel", function() d:delete() end, 2, 2, 1, 1)
  d:show()
end

function descriptor()
  return {
    title = "Party Mode",
    version = "1.0",
    author = "ChatGPT",
    capabilities = {"input-listener"}
  }
end

function activate()
  math.randomseed(os.time())

  local hash = get_pseudo_hash()
  if not hash then
    vlc.msg.err("Could not get video file info")
    return
  end

  local input_item = vlc.input.item()
  local uri = input_item:uri()
  local path = vlc.strings.decode_uri(uri)
  if path:sub(1,7) == "file://" then
    path = path:sub(8)
  end
  local folder = path:match("^(.*)[/\\]")
  reaction_file_path = folder .. "/" .. hash .. ".reactions.json"

  load_reactions()

  username = vlc.config.get("party_mode_username")
  usercolor = vlc.config.get("party_mode_usercolor")

  if username == nil or username == "" then
    ask_username()
  else
    build_ui()
  end
end

function deactivate()
  if dialog then
    dialog:delete()
    dialog = nil
  end
  if overlay_text_id then
    vlc.osd.message("", nil, overlay_text_id)
    overlay_text_id = nil
  end
end

function input_changed()
  last_shown_index = 0
  reactions = { comments = {} }
  activate()
end

function close()
  deactivate()
end

-- Called periodically (every ~1s)
function periodic()
  if not vlc.input or not vlc.input.is_playing() then
    return
  end

  local time = vlc.var.get(vlc.object.input(), "time")
  local comment = find_comment_at(time)
  if comment then
    show_comment(comment)
  end
end

-- Main tick loop: call periodic every second
function tick()
  periodic()
  vlc.misc.mwait(vlc.misc.mdate() + 1000000)
  tick()
end
