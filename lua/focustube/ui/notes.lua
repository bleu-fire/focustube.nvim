local config = require("focustube.config")
local notes = require("focustube.core.notes")
local player = require("focustube.core.player")
local time = require("focustube.utils.time")

local M = {}

--- Open a floating Markdown editor for a single note.
---@param note table
---@param on_saved? fun()
function M.open_editor(note, on_saved)
  local cfg = config.get()
  local width = math.floor(vim.o.columns * math.min(0.70, cfg.ui.width_ratio))
  local height = math.floor(vim.o.lines * math.min(0.65, cfg.ui.height_ratio))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"
  vim.api.nvim_buf_set_name(buf, string.format("focustube://note/%d/%s.md", note.id, note.title))

  local content_lines = vim.split(note.content or "", "\n", { plain = true })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content_lines)
  vim.bo[buf].modified = false

  local ts_label = note.timestamp_sec ~= nil and (" [" .. time.format(note.timestamp_sec) .. "]") or ""
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    border = cfg.ui.border,
    title = " Note: " .. note.title .. ts_label .. " (:w to save, q in normal to close) ",
    title_pos = "center",
  })

  local function save_note()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local body = table.concat(lines, "\n")
    local ok, err = notes.update(note.id, { content = body })
    if ok then
      vim.bo[buf].modified = false
      vim.notify("FocusTube: Note saved", vim.log.levels.INFO)
      if on_saved then
        on_saved()
      end
    else
      vim.notify("FocusTube: " .. tostring(err), vim.log.levels.ERROR)
    end
  end

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = save_note,
  })

  vim.keymap.set("n", "<C-s>", save_note, { buffer = buf, silent = true })
  vim.keymap.set("n", "q", function()
    if vim.bo[buf].modified then
      save_note()
    end
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, nowait = true, silent = true })
end

--- Open the Learning Notes manager for a video.
---@param video table
function M.open(video)
  if not video or not video.id then
    vim.notify("FocusTube: No video selected", vim.log.levels.WARN)
    return
  end

  local cfg = config.get()
  local width = math.floor(vim.o.columns * math.min(0.70, cfg.ui.width_ratio))
  local height = math.floor(vim.o.lines * math.min(0.70, cfg.ui.height_ratio))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "focustube-notes"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = cfg.ui.border,
    title = " FocusTube Notes ",
    title_pos = "center",
  })

  local line_to_note = {}

  local function render()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local items = notes.list(video.id)
    line_to_note = {}

    local lines = {
      "  " .. (video.title or video.id),
      "  " .. string.rep("─", math.max(10, width - 4)),
      "",
    }

    if #items == 0 then
      table.insert(lines, "  No notes yet. Press 'a' to create a learning note.")
    else
      for _, note in ipairs(items) do
        local ts = note.timestamp_sec ~= nil and ("[" .. time.format(note.timestamp_sec) .. "] ") or "[General] "
        local preview = (note.content or ""):gsub("\n", " "):sub(1, 40)
        local suffix = preview ~= "" and (" — " .. preview) or ""
        table.insert(lines, "  " .. ts .. note.title .. suffix)
        line_to_note[#lines] = note
      end
    end

    table.insert(lines, "")
    table.insert(lines, "  " .. string.rep("─", math.max(10, width - 4)))
    table.insert(lines, "  [<CR>/e] Edit  [a] New Note  [x] Export Markdown  [d] Delete  [q] Close")

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
  end

  local function current_note()
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    return line_to_note[cur]
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

  local function edit_selected()
    local note = current_note()
    if note then
      M.open_editor(note, render)
    end
  end
  map("<CR>", edit_selected)
  map("e", edit_selected)

  map("a", function()
    local state = player.get_state()
    local default_ts = ""
    if state.video and state.video.id == video.id and state.position_sec > 0 then
      default_ts = time.format(state.position_sec)
    end
    vim.ui.input({ prompt = "Note title: " }, function(title)
      if not title or vim.trim(title) == "" then
        return
      end
      vim.ui.input({ prompt = "Timestamp (MM:SS, blank for none): ", default = default_ts }, function(ts_str)
        local ts = ts_str and time.parse(ts_str) or nil
        local created, err = notes.create(video.id, {
          title = title,
          timestamp_sec = ts,
          content = "",
        })
        if err or not created then
          vim.notify("FocusTube: " .. tostring(err), vim.log.levels.ERROR)
          return
        end
        render()
        M.open_editor(created, render)
      end)
    end)
  end)

  map("d", function()
    local note = current_note()
    if not note then
      return
    end
    notes.delete(note.id)
    render()
  end)

  map("x", function()
    local md = notes.to_markdown(video)
    vim.cmd("tabnew")
    local exp_buf = vim.api.nvim_get_current_buf()
    vim.bo[exp_buf].buftype = "nofile"
    vim.bo[exp_buf].filetype = "markdown"
    vim.api.nvim_buf_set_lines(exp_buf, 0, -1, false, vim.split(md, "\n", { plain = true }))
  end)

  render()
end

return M
