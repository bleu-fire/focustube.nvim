local config = require("focustube.config")
local json = require("focustube.utils.json")

local M = {}

---@class FocusTubeIPCClient
---@field pipe uv_pipe_t|nil
---@field socket_path string
---@field connected boolean
---@field buffer string
---@field next_id integer
---@field pending table<integer, fun(res: table)>
---@field on_event fun(msg: table)|nil
---@field on_disconnect fun(reason: string|nil)|nil
local Client = {}
Client.__index = Client

--- Create a new mpv Unix domain socket IPC client.
---@param socket_path string
---@param callbacks? { on_event?: fun(msg: table), on_disconnect?: fun(reason: string|nil) }
---@return FocusTubeIPCClient
function M.new(socket_path, callbacks)
  callbacks = callbacks or {}
  return setmetatable({
    pipe = nil,
    socket_path = socket_path,
    connected = false,
    buffer = "",
    next_id = 1,
    pending = {},
    on_event = callbacks.on_event,
    on_disconnect = callbacks.on_disconnect,
  }, Client)
end

--- Connect to the mpv Unix domain socket with retry support.
---@param on_ready fun(ok: boolean, err?: string)
function Client:connect(on_ready)
  local cfg = config.get().player
  local max_retries = cfg.ipc_connect_retries or 25
  local interval = cfg.ipc_retry_interval_ms or 100
  local attempts = 0

  local function try_connect()
    attempts = attempts + 1
    local pipe = vim.uv.new_pipe(false)
    if not pipe then
      vim.schedule(function()
        on_ready(false, "Failed to allocate uv pipe")
      end)
      return
    end

    pipe:connect(self.socket_path, function(err)
      if not err then
        self.pipe = pipe
        self.connected = true
        self:_start_read()
        vim.schedule(function()
          on_ready(true)
        end)
        return
      end

      if not pipe:is_closing() then
        pipe:close()
      end

      if attempts < max_retries then
        local timer = vim.uv.new_timer()
        if timer then
          timer:start(interval, 0, function()
            timer:stop()
            timer:close()
            try_connect()
          end)
          return
        end
      end

      vim.schedule(function()
        on_ready(false, "IPC connect failed: " .. tostring(err))
      end)
    end)
  end

  try_connect()
end

--- Start reading newline-delimited JSON messages from mpv.
function Client:_start_read()
  if not self.pipe then
    return
  end
  self.pipe:read_start(function(err, chunk)
    if err then
      self:close("read error: " .. tostring(err))
      return
    end
    if not chunk then
      self:close("eof")
      return
    end

    self.buffer = self.buffer .. chunk
    while true do
      local nl = self.buffer:find("\n", 1, true)
      if not nl then
        break
      end
      local line = self.buffer:sub(1, nl - 1)
      self.buffer = self.buffer:sub(nl + 1)
      if line ~= "" then
        local msg = json.decode(line)
        if type(msg) == "table" then
          self:_dispatch(msg)
        end
      end
    end
  end)
end

--- Dispatch a decoded JSON message to pending request callbacks or event handler.
---@param msg table
function Client:_dispatch(msg)
  local req_id = msg.request_id
  if req_id and self.pending[req_id] then
    local cb = self.pending[req_id]
    self.pending[req_id] = nil
    vim.schedule(function()
      cb(msg)
    end)
    return
  end

  if msg.event and self.on_event then
    vim.schedule(function()
      if self.on_event then
        self.on_event(msg)
      end
    end)
  end
end

--- Send a JSON IPC command to mpv.
---@param command any[]
---@param cb? fun(res: table)
---@return boolean, string|nil
function Client:send(command, cb)
  if not self.connected or not self.pipe or self.pipe:is_closing() then
    if cb then
      cb({ error = "not connected" })
    end
    return false, "IPC client is not connected"
  end

  local id = self.next_id
  self.next_id = id + 1
  if cb then
    self.pending[id] = cb
  end

  local payload = json.encode({
    command = command,
    request_id = id,
  }) .. "\n"

  self.pipe:write(payload, function(err)
    if err then
      if self.pending[id] then
        local pending_cb = self.pending[id]
        self.pending[id] = nil
        vim.schedule(function()
          pending_cb({ error = tostring(err) })
        end)
      end
    end
  end)

  return true, nil
end

--- Observe an mpv property by name.
---@param observe_id integer
---@param property string
function Client:observe_property(observe_id, property)
  self:send({ "observe_property", observe_id, property })
end

--- Close the IPC connection and notify disconnect handler once.
---@param reason? string
function Client:close(reason)
  local was_connected = self.connected
  self.connected = false

  for id, cb in pairs(self.pending) do
    self.pending[id] = nil
    vim.schedule(function()
      cb({ error = reason or "disconnected" })
    end)
  end

  if self.pipe and not self.pipe:is_closing() then
    pcall(function()
      self.pipe:read_stop()
    end)
    self.pipe:close()
  end
  self.pipe = nil

  if was_connected and self.on_disconnect then
    local on_disc = self.on_disconnect
    self.on_disconnect = nil
    vim.schedule(function()
      on_disc(reason)
    end)
  end
end

return M
