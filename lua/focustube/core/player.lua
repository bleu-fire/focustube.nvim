local config = require("focustube.config")
local ipc = require("focustube.core.ipc")
local library = require("focustube.core.library")
local progress = require("focustube.core.progress")
local paths = require("focustube.utils.paths")
local system = require("focustube.utils.system")

local M = {}

M._state = {
  video = nil,
  proc = nil,
  ipc_client = nil,
  socket_path = nil,
  playing = false,
  paused = false,
  position_sec = 0,
  duration_sec = 0,
  listeners = {},
}

--- Subscribe to player state updates. Returns an unsubscribe function.
---@param fn fun(state: table)
---@return fun()
function M.subscribe(fn)
  table.insert(M._state.listeners, fn)
  return function()
    for i, cb in ipairs(M._state.listeners) do
      if cb == fn then
        table.remove(M._state.listeners, i)
        break
      end
    end
  end
end

function M._notify()
  local snap = M.get_state()
  for _, fn in ipairs(M._state.listeners) do
    pcall(fn, snap)
  end
end

--- Return a snapshot of current player state.
---@return table
function M.get_state()
  return {
    video = M._state.video,
    playing = M._state.playing,
    paused = M._state.paused,
    position_sec = M._state.position_sec,
    duration_sec = M._state.duration_sec,
  }
end

--- Check if mpv is currently active.
---@return boolean
function M.is_active()
  return M._state.proc ~= nil and M._state.playing
end

--- Clean up process, IPC client, progress tracking, and socket file.
function M._cleanup()
  progress.stop_tracking()

  if M._state.ipc_client then
    M._state.ipc_client:close("cleanup")
    M._state.ipc_client = nil
  end

  paths.remove_file(M._state.socket_path)
  M._state.socket_path = nil
  M._state.proc = nil
  M._state.playing = false
  M._state.paused = false
  M._notify()
end

--- Play an approved video from the local library in external mpv.
---@param video_id string
---@param opts? { start_sec?: number, on_ready?: fun(ok: boolean, err?: string) }
---@return boolean, string|nil
function M.play(video_id, opts)
  opts = opts or {}

  local focus = require("focustube.core.focus")
  if not focus.can_switch_video(video_id) then
    return false, "Focus Mode is active: finish or exit Focus Mode before switching videos"
  end

  local video = library.get(video_id)
  if not video then
    return false, "Video is not in your approved FocusTube library"
  end

  local cfg = config.get()
  local mpv_bin = cfg.binaries.mpv
  if not system.has_executable(mpv_bin) then
    return false, "mpv executable not found: " .. mpv_bin
  end

  if M.is_active() then
    M.stop()
  end

  local socket_path = paths.ipc_socket_path()
  paths.remove_file(socket_path)

  local start_sec = opts.start_sec
  if start_sec == nil then
    start_sec = progress.get_resume_position(video)
  end

  local args = { mpv_bin }
  for _, a in ipairs(cfg.player.mpv_args or {}) do
    table.insert(args, a)
  end
  table.insert(args, "--input-ipc-server=" .. socket_path)
  if start_sec > 0 then
    table.insert(args, "--start=" .. tostring(math.floor(start_sec)))
  end
  if system.has_executable(cfg.binaries.deno) then
    table.insert(args, "--ytdl-raw-options=js-runtimes=deno")
  end
  table.insert(args, video.url)

  M._state.video = video
  M._state.socket_path = socket_path
  M._state.playing = true
  M._state.paused = false
  M._state.position_sec = start_sec
  M._state.duration_sec = tonumber(video.duration_sec) or 0

  progress.start_tracking(video.id, start_sec, M._state.duration_sec)

  local proc = vim.system(args, { detach = false }, function(_res)
    vim.schedule(function()
      M._cleanup()
    end)
  end)
  M._state.proc = proc

  local client = ipc.new(socket_path, {
    on_event = function(msg)
      M._handle_ipc_event(msg)
    end,
    on_disconnect = function()
      progress.flush()
    end,
  })
  M._state.ipc_client = client

  client:connect(function(ok, err)
    if ok then
      client:observe_property(1, "time-pos")
      client:observe_property(2, "duration")
      client:observe_property(3, "pause")
      client:observe_property(4, "eof-reached")
    else
      vim.notify("FocusTube mpv IPC warning: " .. tostring(err), vim.log.levels.WARN)
    end
    M._notify()
    if opts.on_ready then
      opts.on_ready(ok, err)
    end
  end)

  M._notify()
  return true, nil
end

--- Handle incoming mpv IPC events.
---@param msg table
function M._handle_ipc_event(msg)
  if msg.event == "property-change" then
    if msg.name == "time-pos" and type(msg.data) == "number" then
      M._state.position_sec = msg.data
      progress.update(msg.data, nil)
      M._notify()
    elseif msg.name == "duration" and type(msg.data) == "number" and msg.data > 0 then
      M._state.duration_sec = msg.data
      progress.update(nil, msg.data)
      M._notify()
    elseif msg.name == "pause" and type(msg.data) == "boolean" then
      M._state.paused = msg.data
      if msg.data then
        progress.flush()
      end
      M._notify()
    elseif msg.name == "eof-reached" and msg.data == true then
      progress.flush()
    end
  elseif msg.event == "end-file" then
    progress.flush()
  end
end

--- Pause playback.
function M.pause()
  if M._state.ipc_client and M._state.ipc_client.connected then
    M._state.ipc_client:send({ "set_property", "pause", true })
    progress.flush()
  end
end

--- Resume playback.
function M.resume()
  if M._state.ipc_client and M._state.ipc_client.connected then
    M._state.ipc_client:send({ "set_property", "pause", false })
  end
end

--- Toggle pause/resume.
function M.toggle_pause()
  if M._state.ipc_client and M._state.ipc_client.connected then
    M._state.ipc_client:send({ "cycle", "pause" })
  end
end

--- Seek in current video.
---@param seconds number
---@param mode? "relative"|"absolute"
function M.seek(seconds, mode)
  mode = mode or "relative"
  if M._state.ipc_client and M._state.ipc_client.connected then
    M._state.ipc_client:send({ "seek", seconds, mode })
    if mode == "absolute" then
      M._state.position_sec = math.max(0, seconds)
      progress.update(M._state.position_sec, nil)
      progress.flush()
      M._notify()
    end
  end
end

--- Stop the external mpv player and save progress.
function M.stop()
  progress.flush()
  if M._state.ipc_client and M._state.ipc_client.connected then
    M._state.ipc_client:send({ "quit" })
  end
  if M._state.proc then
    pcall(function()
      M._state.proc:kill("sigterm")
    end)
  end
  M._cleanup()
end

return M
