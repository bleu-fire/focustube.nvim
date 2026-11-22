local bookmarks = require("focustube.core.bookmarks")
local config = require("focustube.config")
local focus = require("focustube.core.focus")
local library = require("focustube.core.library")
local notes = require("focustube.core.notes")
local player = require("focustube.core.player")
local progress = require("focustube.core.progress")
local time = require("focustube.utils.time")

local M = {}

--- Open the focused single-video workspace.
---@param video_id string
function M.open(video_id)
  local video = library.get(video_id)
  if not video then
    vim.notify("FocusTube: Video not found in library", vim.log.levels.ERROR)
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
  vim.bo[buf].filetype = "focustube-video"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = cfg.ui.border,
    title = " FocusTube Video Workspace ",
    title_pos = "center",
  })

  local unsub = nil

  local function render()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local fresh = library.get(video.id) or video
    local pstate = player.get_state()
    local is_this_playing = pstate.video and pstate.video.id == fresh.id and pstate.playing
    local pos = is_this_playing and pstate.position_sec or (tonumber(fresh.position_sec) or 0)
    local dur = is_this_playing and pstate.duration_sec > 0 and pstate.duration_sec
      or (tonumber(fresh.duration_sec) or 0)

    local status_str = "Stopped"
    if is_this_playing then
      status_str = pstate.paused and "Paused" or "Playing (mpv)"
    elseif fresh.completed == 1 then
      status_str = "Completed"
    end

    local fstatus = focus.status()
    local focus_str = fstatus.active and fstatus.video_id == fresh.id
        and string.format("FOCUS MODE ON (%s)", time.format(fstatus.elapsed_sec))
      or "Focus Mode: Off"

    local bms = bookmarks.list(fresh.id)
    local nts = notes.list(fresh.id)

    local lines = {
      "  " .. fresh.title,
      string.format("  Channel: %s   |   Category: %s   |   %s", fresh.channel or "Unknown", fresh.category, focus_str),
      "  " .. string.rep("─", math.max(10, width - 4)),
      string.format(
        "  %s   %s / %s   [%s]",
        time.progress_bar(pos, dur, 26),
        time.format(pos),
        time.format(dur),
        status_str
      ),
      "",
      "  Bookmarks (" .. #bms .. "):",
    }

    if #bms == 0 then
      table.insert(lines, "    (none — press 'b' to capture timestamp)")
    else
      for i = 1, math.min(5, #bms) do
        table.insert(lines, "    " .. bookmarks.format_line(bms[i]))
      end
      if #bms > 5 then
        table.insert(lines, string.format("    ... and %d more (press 'B' to view all)", #bms - 5))
      end
    end

    table.insert(lines, "")
    table.insert(lines, "  Learning Notes (" .. #nts .. "):")
    if #nts == 0 then
      table.insert(lines, "    (none — press 'n' to create a note)")
    else
      for i = 1, math.min(5, #nts) do
        local ts = nts[i].timestamp_sec ~= nil and ("[" .. time.format(nts[i].timestamp_sec) .. "] ") or ""
        table.insert(lines, "    " .. ts .. nts[i].title)
      end
      if #nts > 5 then
        table.insert(lines, string.format("    ... and %d more (press 'N' to view all)", #nts - 5))
      end
    end

    table.insert(lines, "")
    table.insert(lines, "  " .. string.rep("─", math.max(10, width - 4)))
    table.insert(lines, "  [p] Play  [<Space>] Pause/Resume  [h/l] -10s/+10s  [s] Stop  [f] Focus Mode")
    table.insert(lines, "  [b] Add Bookmark  [B] Bookmarks  [n] Add Note  [N] Notes  [m] Complete  [q] Close")

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
  end

  unsub = player.subscribe(function()
    render()
  end)

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    callback = function()
      if unsub then
        unsub()
        unsub = nil
      end
    end,
  })

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

  map("p", function()
    local ok, err = player.play(video.id)
    if not ok then
      vim.notify("FocusTube: " .. tostring(err), vim.log.levels.ERROR)
    end
    render()
  end)

  map("<Space>", function()
    player.toggle_pause()
  end)

  map("h", function()
    player.seek(-(cfg.player.seek_step or 10), "relative")
  end)
  map("l", function()
    player.seek(cfg.player.seek_step or 10, "relative")
  end)

  map("s", function()
    player.stop()
    render()
  end)

  map("f", function()
    local ok, err = focus.toggle(video.id)
    if not ok then
      vim.notify("FocusTube: " .. tostring(err), vim.log.levels.ERROR)
    end
    render()
  end)

  map("m", function()
    local fresh = library.get(video.id)
    if fresh then
      progress.mark_completed(video.id, fresh.completed ~= 1)
      render()
    end
  end)

  map("b", function()
    local pstate = player.get_state()
    local ts = (pstate.video and pstate.video.id == video.id) and pstate.position_sec or (video.position_sec or 0)
    vim.ui.input({ prompt = string.format("Bookmark at %s: ", time.format(ts)) }, function(input)
      if not input then
        return
      end
      bookmarks.add(video.id, ts, input)
      render()
    end)
  end)

  map("B", function()
    require("focustube.ui.bookmarks").open(library.get(video.id) or video)
  end)

  map("n", function()
    local pstate = player.get_state()
    local ts = (pstate.video and pstate.video.id == video.id) and pstate.position_sec or nil
    vim.ui.input({ prompt = "Note title: " }, function(title)
      if not title or vim.trim(title) == "" then
        return
      end
      local created = notes.create(video.id, { title = title, timestamp_sec = ts, content = "" })
      if created then
        render()
        require("focustube.ui.notes").open_editor(created, render)
      end
    end)
  end)

  map("N", function()
    require("focustube.ui.notes").open(library.get(video.id) or video)
  end)

  render()
end

return M
