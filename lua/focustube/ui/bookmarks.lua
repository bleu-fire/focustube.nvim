local bookmarks = require("focustube.core.bookmarks")
local player = require("focustube.core.player")
local time = require("focustube.utils.time")
local config = require("focustube.config")

local M = {}

--- Open the Timestamp Bookmarks floating window for a video.
---@param video table
function M.open(video)
  if not video or not video.id then
    vim.notify("FocusTube: No video selected", vim.log.levels.WARN)
    return
  end

  local cfg = config.get()
  local width = math.floor(vim.o.columns * math.min(0.65, cfg.ui.width_ratio))
  local height = math.floor(vim.o.lines * math.min(0.65, cfg.ui.height_ratio))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "focustube-bookmarks"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = cfg.ui.border,
    title = " FocusTube Bookmarks ",
    title_pos = "center",
  })

  local items = {}
  local line_to_item = {}

  local function render()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    items = bookmarks.list(video.id)
    line_to_item = {}

    local lines = {
      "  " .. (video.title or video.id),
      "  " .. string.rep("─", math.max(10, width - 4)),
      "",
    }

    if #items == 0 then
      table.insert(lines, "  No bookmarks yet. Press 'a' to capture the current timestamp.")
    else
      for _, bm in ipairs(items) do
        table.insert(lines, "  " .. bookmarks.format_line(bm))
        line_to_item[#lines] = bm
      end
    end

    table.insert(lines, "")
    table.insert(lines, "  " .. string.rep("─", math.max(10, width - 4)))
    table.insert(lines, "  [<CR>] Jump  [a] Add at current time  [e] Rename  [d] Delete  [q] Close")

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
  end

  local function current_bookmark()
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    return line_to_item[cur]
  end

  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
  end

  map("q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end)
  map("<Esc>", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end)

  map("<CR>", function()
    local bm = current_bookmark()
    if not bm then
      return
    end
    local state = player.get_state()
    if state.video and state.video.id == video.id and player.is_active() then
      player.seek(bm.timestamp_sec, "absolute")
      vim.notify("Jumped to " .. time.format(bm.timestamp_sec), vim.log.levels.INFO)
    else
      player.play(video.id, { start_sec = bm.timestamp_sec })
    end
  end)

  map("a", function()
    local state = player.get_state()
    local ts = (state.video and state.video.id == video.id) and state.position_sec or (video.position_sec or 0)
    vim.ui.input({ prompt = string.format("Bookmark title (%s): ", time.format(ts)) }, function(input)
      if not input then
        return
      end
      local _, err = bookmarks.add(video.id, ts, input)
      if err then
        vim.notify("FocusTube: " .. err, vim.log.levels.ERROR)
      else
        render()
      end
    end)
  end)

  map("e", function()
    local bm = current_bookmark()
    if not bm then
      return
    end
    vim.ui.input({ prompt = "Rename bookmark: ", default = bm.title }, function(input)
      if not input or vim.trim(input) == "" then
        return
      end
      bookmarks.update(bm.id, { title = input })
      render()
    end)
  end)

  map("d", function()
    local bm = current_bookmark()
    if not bm then
      return
    end
    bookmarks.delete(bm.id)
    render()
  end)

  render()
end

return M
