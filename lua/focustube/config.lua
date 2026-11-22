local M = {}

---@class FocusTubeConfig
M.defaults = {
  db_path = nil, -- Defaults to stdpath("data")/focustube/focustube.db
  binaries = {
    mpv = "mpv",
    yt_dlp = "yt-dlp",
    deno = "deno",
    sqlite3 = "sqlite3",
  },
  player = {
    mpv_args = {
      "--no-terminal",
      "--force-window=yes",
      "--keep-open=yes",
    },
    seek_step = 10,
    ipc_connect_retries = 25,
    ipc_retry_interval_ms = 100,
  },
  progress = {
    save_interval_ms = 5000,
    completion_threshold = 0.90, -- 90% watched marks video completed
    resume_margin_sec = 5,
  },
  focus = {
    block_browsing = true,
    hide_watch_later = true,
    hide_categories = true,
  },
  ui = {
    border = "rounded",
    width_ratio = 0.80,
    height_ratio = 0.80,
  },
  keymaps = {
    enable_default = true,
  },
}

---@type FocusTubeConfig
M.options = vim.deepcopy(M.defaults)

--- Merge user configuration with defaults.
---@param opts? table
---@return FocusTubeConfig
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.options
end

--- Get current configuration.
---@return FocusTubeConfig
function M.get()
  return M.options
end

return M
