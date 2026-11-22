local M = {}

--- Ensure a directory exists.
---@param dir string
---@return string
function M.ensure_dir(dir)
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
  return dir
end

--- Default SQLite database path inside Neovim data directory.
---@param custom_path? string
---@return string
function M.db_path(custom_path)
  if custom_path and custom_path ~= "" then
    M.ensure_dir(vim.fs.dirname(custom_path))
    return custom_path
  end
  local data_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "focustube")
  M.ensure_dir(data_dir)
  return vim.fs.joinpath(data_dir, "focustube.db")
end

--- Generate a unique Unix domain socket path for mpv IPC.
--- Never uses TCP or network sockets.
---@return string
function M.ipc_socket_path()
  local runtime_dir = vim.env.XDG_RUNTIME_DIR
  if not runtime_dir or runtime_dir == "" then
    runtime_dir = vim.fs.joinpath(vim.fn.stdpath("state"), "focustube")
  else
    runtime_dir = vim.fs.joinpath(runtime_dir, "focustube")
  end
  M.ensure_dir(runtime_dir)
  local pid = vim.uv.os_getpid()
  local hr = vim.uv.hrtime()
  return vim.fs.joinpath(runtime_dir, string.format("mpv-%d-%d.sock", pid, hr))
end

--- Remove a socket file if it exists.
---@param path string|nil
function M.remove_file(path)
  if path and path ~= "" and vim.uv.fs_stat(path) then
    pcall(vim.uv.fs_unlink, path)
  end
end

return M
