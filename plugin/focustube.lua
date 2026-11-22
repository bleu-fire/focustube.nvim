if vim.g.loaded_focustube then
  return
end
vim.g.loaded_focustube = 1

-- Lightweight lazy command registration before setup() is explicitly called.
vim.api.nvim_create_user_command("FocusTube", function()
  require("focustube").open()
end, { desc = "Open FocusTube Dashboard" })
