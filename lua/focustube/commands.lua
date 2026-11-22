local M = {}

--- Register FocusTube user commands and optional default keymaps.
function M.register()
  local config = require("focustube.config")
  local bookmarks = require("focustube.core.bookmarks")
  local focus = require("focustube.core.focus")
  local library = require("focustube.core.library")
  local notes = require("focustube.core.notes")
  local player = require("focustube.core.player")
  local system = require("focustube.utils.system")
  local time = require("focustube.utils.time")

  vim.api.nvim_create_user_command("FocusTube", function()
    require("focustube.ui.dashboard").open()
  end, { desc = "Open FocusTube Dashboard" })

  vim.api.nvim_create_user_command("FocusTubeLibrary", function()
    require("focustube.ui.library").open()
  end, { desc = "Open FocusTube Video Library" })

  vim.api.nvim_create_user_command("FocusTubeAdd", function(opts)
    local url = vim.trim(opts.args or "")
    local function add(target_url)
      vim.notify("FocusTube: Fetching metadata via yt-dlp...", vim.log.levels.INFO)
      library.add_url(target_url, {}, function(saved, err)
        if err or not saved then
          vim.notify("FocusTube: " .. tostring(err), vim.log.levels.ERROR)
          return
        end
        vim.notify("FocusTube: Added '" .. saved.title .. "'", vim.log.levels.INFO)
      end)
    end
    if url ~= "" then
      add(url)
    else
      vim.ui.input({ prompt = "YouTube Video URL: " }, function(input)
        if input and vim.trim(input) ~= "" then
          add(input)
        end
      end)
    end
  end, { nargs = "?", desc = "Add a YouTube URL to FocusTube library" })

  vim.api.nvim_create_user_command("FocusTubePause", function()
    player.toggle_pause()
  end, { desc = "Toggle pause/resume in mpv" })

  vim.api.nvim_create_user_command("FocusTubeStop", function()
    player.stop()
  end, { desc = "Stop mpv playback and save progress" })

  vim.api.nvim_create_user_command("FocusTubeSeek", function(opts)
    local sec = tonumber(opts.args)
    if not sec then
      vim.notify("FocusTubeSeek: provide numeric seconds (e.g. +15 or -10)", vim.log.levels.WARN)
      return
    end
    player.seek(sec, "relative")
  end, { nargs = 1, desc = "Seek relative seconds in mpv" })

  vim.api.nvim_create_user_command("FocusTubeBookmark", function(opts)
    local pstate = player.get_state()
    if not pstate.video then
      vim.notify("FocusTube: No active video", vim.log.levels.WARN)
      return
    end
    local ts = pstate.position_sec or 0
    local title = vim.trim(opts.args or "")
    if title ~= "" then
      bookmarks.add(pstate.video.id, ts, title)
      vim.notify("FocusTube: Bookmarked " .. time.format(ts), vim.log.levels.INFO)
    else
      vim.ui.input({ prompt = string.format("Bookmark at %s: ", time.format(ts)) }, function(input)
        if input then
          bookmarks.add(pstate.video.id, ts, input)
          vim.notify("FocusTube: Bookmarked " .. time.format(ts), vim.log.levels.INFO)
        end
      end)
    end
  end, { nargs = "?", desc = "Capture a timestamp bookmark for the active video" })

  vim.api.nvim_create_user_command("FocusTubeNote", function()
    local pstate = player.get_state()
    local target = pstate.video or library.list()[1]
    if not target then
      vim.notify("FocusTube: No video selected", vim.log.levels.WARN)
      return
    end
    local ts = (pstate.video and pstate.video.id == target.id) and pstate.position_sec or nil
    vim.ui.input({ prompt = "Note title: " }, function(title)
      if not title or vim.trim(title) == "" then
        return
      end
      local created = notes.create(target.id, { title = title, timestamp_sec = ts, content = "" })
      if created then
        require("focustube.ui.notes").open_editor(created)
      end
    end)
  end, { desc = "Create a learning note for the active video" })

  vim.api.nvim_create_user_command("FocusTubeFocus", function()
    if focus.is_active() then
      focus.disable()
      vim.notify("FocusTube: Focus Mode disabled", vim.log.levels.INFO)
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
    vim.notify("FocusTube: Focus Mode enabled for '" .. target.title .. "'", vim.log.levels.INFO)
  end, { desc = "Toggle FocusTube Focus Mode" })

  vim.api.nvim_create_user_command("FocusTubeHealth", function()
    local bins = config.get().binaries
    local report = {
      string.format("mpv:     %s", system.has_executable(bins.mpv) and "OK" or "MISSING"),
      string.format("yt-dlp:  %s", system.has_executable(bins.yt_dlp) and "OK" or "MISSING"),
      string.format("deno:    %s", system.has_executable(bins.deno) and "OK" or "MISSING"),
      string.format("sqlite3: %s", system.has_executable(bins.sqlite3) and "OK" or "MISSING"),
    }
    vim.notify("FocusTube Health:\n" .. table.concat(report, "\n"), vim.log.levels.INFO)
  end, { desc = "Check FocusTube external dependencies" })

  if config.get().keymaps.enable_default then
    local map = function(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, { silent = true, desc = desc })
    end
    map("<leader>ftd", "<cmd>FocusTube<cr>", "FocusTube Dashboard")
    map("<leader>ftl", "<cmd>FocusTubeLibrary<cr>", "FocusTube Library")
    map("<leader>fta", "<cmd>FocusTubeAdd<cr>", "FocusTube Add URL")
    map("<leader>ftp", "<cmd>FocusTubePause<cr>", "FocusTube Pause/Resume")
    map("<leader>ftb", "<cmd>FocusTubeBookmark<cr>", "FocusTube Add Bookmark")
    map("<leader>ftn", "<cmd>FocusTubeNote<cr>", "FocusTube New Note")
    map("<leader>ftf", "<cmd>FocusTubeFocus<cr>", "FocusTube Toggle Focus Mode")
  end
end

return M
