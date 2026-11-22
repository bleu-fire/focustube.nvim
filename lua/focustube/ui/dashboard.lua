local config = require("focustube.config")
local focus = require("focustube.core.focus")
local library = require("focustube.core.library")
local player = require("focustube.core.player")
local time = require("focustube.utils.time")

local M = {}

--- Open the main FocusTube Dashboard.
--- In Focus Mode, hides unnecessary browsing elements and locks onto the active video.
function M.open()
  local cfg = config.get()
  local width = math.floor(vim.o.columns * math.min(0.65, cfg.ui.width_ratio))
  local height = math.floor(vim.o.lines * math.min(0.55, cfg.ui.height_ratio))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "focustube-dashboard"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = cfg.ui.border,
    title = " FocusTube ",
    title_pos = "center",
  })

  local function render()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    local fstatus = focus.status()
    local pstate = player.get_state()
    local lines = {}

    if fstatus.active and fstatus.video_id then
      -- Minimal, distraction-free Focus Mode dashboard
      local v = library.get(fstatus.video_id)
      local pos = (pstate.video and pstate.video.id == fstatus.video_id and pstate.playing)
          and pstate.position_sec
        or (v and v.position_sec or 0)
      local dur = (v and v.duration_sec or 0)

      lines = {
        "",
        "  FOCUS MODE ACTIVE",
        "  " .. string.rep("─", math.max(10, width - 4)),
        "",
        "  Video:    " .. (v and v.title or fstatus.video_id),
        "  Progress: " .. time.progress_bar(pos, dur, 22) .. "  (" .. time.format(pos) .. " / " .. time.format(dur) .. ")",
        "  Session:  " .. time.format(fstatus.elapsed_sec) .. " elapsed",
        "",
        "  " .. string.rep("─", math.max(10, width - 4)),
        "  [<CR>] Open Video Workspace   [<Space>] Pause/Resume",
        "  [b] Bookmarks   [n] Notes   [F] Exit Focus Mode   [q] Close",
      }
    else
      local stats = library.stats()
      local current_v = pstate.video
      if not current_v then
        local all = library.list()
        current_v = all[1]
      end

      lines = {
        "",
        "  FocusTube — Intentional YouTube Learning",
        "  " .. string.rep("─", math.max(10, width - 4)),
        "",
        string.format(
          "  Library: %d videos   |   In Progress: %d   |   Completed: %d   |   Watch Later: %d",
          stats.total,
          stats.in_progress,
          stats.completed,
          stats.watch_later
        ),
        "",
      }

      if current_v then
        table.insert(lines, "  Up Next / Active: " .. current_v.title)
        table.insert(
          lines,
          string.format(
            "  %s  (%s / %s)",
            time.progress_bar(current_v.position_sec, current_v.duration_sec, 22),
            time.format(current_v.position_sec),
            time.format(current_v.duration_sec)
          )
        )
      else
        table.insert(lines, "  Your library is empty. Press 'a' to add a YouTube URL.")
      end

      table.insert(lines, "")
      table.insert(lines, "  " .. string.rep("─", math.max(10, width - 4)))
      table.insert(lines, "  [l] Library   [w] Watch Later   [a] Add URL   [v] Video Workspace")
      table.insert(lines, "  [f] Start Focus Mode   [q] Close")
    end

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
  end

  local function close_win()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
  end

  map("q", close_win)
  map("<Esc>", close_win)

  map("<Space>", function()
    player.toggle_pause()
  end)

  map("<CR>", function()
    local fstatus = focus.status()
    local target_id = fstatus.video_id
    if not target_id then
      local pstate = player.get_state()
      target_id = pstate.video and pstate.video.id or nil
    end
    if target_id then
      close_win()
      require("focustube.ui.video").open(target_id)
    end
  end)

  map("v", function()
    local pstate = player.get_state()
    local target = pstate.video or library.list()[1]
    if target then
      close_win()
      require("focustube.ui.video").open(target.id)
    end
  end)

  map("l", function()
    if not focus.can_browse() then
      vim.notify("FocusTube: Library browsing is disabled during Focus Mode", vim.log.levels.WARN)
      return
    end
    close_win()
    require("focustube.ui.library").open()
  end)

  map("w", function()
    if not focus.can_browse() then
      vim.notify("FocusTube: Watch-Later browsing is disabled during Focus Mode", vim.log.levels.WARN)
      return
    end
    close_win()
    require("focustube.ui.library").open({ watch_later = true })
  end)

  map("a", function()
    if focus.is_active() then
      vim.notify("FocusTube: Exit Focus Mode before adding new videos", vim.log.levels.WARN)
      return
    end
    vim.ui.input({ prompt = "YouTube Video URL: " }, function(url)
      if not url or vim.trim(url) == "" then
        return
      end
      vim.notify("FocusTube: Fetching metadata via yt-dlp...", vim.log.levels.INFO)
      library.add_url(url, {}, function(saved, err)
        if err or not saved then
          vim.notify("FocusTube: " .. tostring(err), vim.log.levels.ERROR)
          return
        end
        vim.notify("FocusTube: Added '" .. saved.title .. "'", vim.log.levels.INFO)
        render()
      end)
    end)
  end)

  map("b", function()
    local fstatus = focus.status()
    local target_id = fstatus.video_id or (player.get_state().video and player.get_state().video.id)
    if target_id then
      local v = library.get(target_id)
      if v then
        require("focustube.ui.bookmarks").open(v)
      end
    end
  end)

  map("n", function()
    local fstatus = focus.status()
    local target_id = fstatus.video_id or (player.get_state().video and player.get_state().video.id)
    if target_id then
      local v = library.get(target_id)
      if v then
        require("focustube.ui.notes").open(v)
      end
    end
  end)

  map("f", function()
    if focus.is_active() then
      return
    end
    local pstate = player.get_state()
    local target = pstate.video or library.list()[1]
    if not target then
      vim.notify("FocusTube: Add a video first before starting Focus Mode", vim.log.levels.WARN)
      return
    end
    local ok, err = focus.enable(target.id)
    if not ok then
      vim.notify("FocusTube: " .. tostring(err), vim.log.levels.ERROR)
      return
    end
    player.play(target.id)
    render()
  end)

  map("F", function()
    if focus.is_active() then
      focus.disable()
      vim.notify("FocusTube: Focus Mode ended", vim.log.levels.INFO)
      render()
    end
  end)

  render()
end

return M
