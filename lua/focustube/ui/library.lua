local config = require("focustube.config")
local focus = require("focustube.core.focus")
local library = require("focustube.core.library")
local player = require("focustube.core.player")
local progress = require("focustube.core.progress")
local time = require("focustube.utils.time")

local M = {}

--- Open the Video Library floating window.
---@param opts? { watch_later?: boolean, category?: string }
function M.open(opts)
  opts = opts or {}

  if not focus.can_browse() then
    local fstatus = focus.status()
    vim.notify(
      "FocusTube: Library browsing is locked during Focus Mode. Exit Focus Mode first.",
      vim.log.levels.WARN
    )
    if fstatus.video_id then
      require("focustube.ui.video").open(fstatus.video_id)
    end
    return
  end

  local cfg = config.get()
  local width = math.floor(vim.o.columns * cfg.ui.width_ratio)
  local height = math.floor(vim.o.lines * cfg.ui.height_ratio)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "focustube-library"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = cfg.ui.border,
    title = " FocusTube Library ",
    title_pos = "center",
  })

  local state = {
    category = opts.category or "All",
    watch_later_only = opts.watch_later or false,
    search = nil,
  }
  local line_to_video = {}

  local function render()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local videos = library.list({
      category = state.category,
      watch_later = state.watch_later_only and true or nil,
      search = state.search,
    })
    line_to_video = {}

    local filter_label = string.format(
      "  Category: %s   |   Queue: %s%s",
      state.category,
      state.watch_later_only and "Watch Later" or "All",
      state.search and ("   |   Search: " .. state.search) or ""
    )

    local lines = {
      filter_label,
      "  " .. string.rep("─", math.max(10, width - 4)),
      "",
    }

    if #videos == 0 then
      table.insert(lines, "  No videos match this filter. Press 'a' to add a YouTube URL.")
    else
      for _, v in ipairs(videos) do
        local icon = v.completed == 1 and "[✓]" or (v.position_sec > 0 and "[▶]" or "[ ]")
        local wl = v.watch_later == 1 and " ★" or ""
        local pct = v.duration_sec > 0 and math.floor((v.position_sec / v.duration_sec) * 100 + 0.5) or 0
        local line = string.format(
          "  %s %-46s  %8s  %3d%%  [%s]%s",
          icon,
          v.title:sub(1, 46),
          time.format(v.duration_sec),
          pct,
          v.category,
          wl
        )
        table.insert(lines, line)
        line_to_video[#lines] = v
      end
    end

    table.insert(lines, "")
    table.insert(lines, "  " .. string.rep("─", math.max(10, width - 4)))
    table.insert(lines, "  [<CR>] Play  [v] Workspace  [f] Focus+Play  [a] Add URL  [W] WatchLater  [<Tab>] Category")
    table.insert(lines, "  [c] Set Category  [m] Complete  [/] Search  [d] Delete  [q] Close")

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
  end

  local function current_video()
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    return line_to_video[cur]
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
    local v = current_video()
    if not v then
      return
    end
    local ok, err = player.play(v.id)
    if not ok then
      vim.notify("FocusTube: " .. tostring(err), vim.log.levels.ERROR)
    end
  end)

  map("v", function()
    local v = current_video()
    if not v then
      return
    end
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    require("focustube.ui.video").open(v.id)
  end)

  map("f", function()
    local v = current_video()
    if not v then
      return
    end
    local ok, err = focus.enable(v.id)
    if not ok then
      vim.notify("FocusTube: " .. tostring(err), vim.log.levels.ERROR)
      return
    end
    player.play(v.id)
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    require("focustube.ui.video").open(v.id)
  end)

  map("a", function()
    vim.ui.input({ prompt = "YouTube Video URL: " }, function(url)
      if not url or vim.trim(url) == "" then
        return
      end
      vim.notify("FocusTube: Fetching metadata via yt-dlp...", vim.log.levels.INFO)
      library.add_url(url, { category = state.category ~= "All" and state.category or "General" }, function(saved, err)
        if err or not saved then
          vim.notify("FocusTube: " .. tostring(err), vim.log.levels.ERROR)
          return
        end
        vim.notify("FocusTube: Added '" .. saved.title .. "'", vim.log.levels.INFO)
        render()
      end)
    end)
  end)

  map("W", function()
    local v = current_video()
    if not v then
      return
    end
    library.toggle_watch_later(v.id)
    render()
  end)

  map("w", function()
    state.watch_later_only = not state.watch_later_only
    render()
  end)

  map("<Tab>", function()
    local cats = library.categories()
    local idx = 1
    for i, c in ipairs(cats) do
      if c == state.category then
        idx = (i % #cats) + 1
        break
      end
    end
    state.category = cats[idx] or "All"
    render()
  end)

  map("c", function()
    local v = current_video()
    if not v then
      return
    end
    vim.ui.input({ prompt = "Category: ", default = v.category }, function(cat)
      if not cat or vim.trim(cat) == "" then
        return
      end
      library.set_category(v.id, cat)
      render()
    end)
  end)

  map("m", function()
    local v = current_video()
    if not v then
      return
    end
    progress.mark_completed(v.id, v.completed ~= 1)
    render()
  end)

  map("/", function()
    vim.ui.input({ prompt = "Search title/channel (blank clears): ", default = state.search or "" }, function(q)
      state.search = (q and vim.trim(q) ~= "") and vim.trim(q) or nil
      render()
    end)
  end)

  map("d", function()
    local v = current_video()
    if not v then
      return
    end
    library.delete(v.id)
    render()
  end)

  render()
end

return M
