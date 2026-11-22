local config = require("focustube.config")

local M = {}

M._setup_done = false

--- Configure and initialize FocusTube.nvim.
---@param opts? table
function M.setup(opts)
  config.setup(opts)

  if M._setup_done then
    return
  end
  M._setup_done = true

  local db = require("focustube.core.database")
  local ok, err = db.init()
  if not ok then
    vim.notify("FocusTube DB init error: " .. tostring(err), vim.log.levels.ERROR)
  end

  require("focustube.commands").register()

  local group = vim.api.nvim_create_augroup("FocusTubeLifecycle", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      local focus = require("focustube.core.focus")
      local player = require("focustube.core.player")
      if player.is_active() then
        player.stop()
      end
      if focus.is_active() then
        focus.disable()
      end
    end,
  })
end

--- Open the FocusTube Dashboard.
function M.open()
  if not M._setup_done then
    M.setup()
  end
  require("focustube.ui.dashboard").open()
end

return M
