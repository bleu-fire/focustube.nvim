local db = require("focustube.core.database")
local time = require("focustube.utils.time")

local M = {}

--- Create a learning note associated with a video and optional timestamp.
---@param video_id string
---@param opts { title: string, content?: string, timestamp_sec?: number|nil }
---@return table|nil, string|nil
function M.create(video_id, opts)
  if not video_id or video_id == "" then
    return nil, "Invalid video_id"
  end
  opts = opts or {}
  local title = vim.trim(opts.title or "")
  if title == "" then
    return nil, "Note title cannot be empty"
  end
  local ts = opts.timestamp_sec ~= nil and math.max(0, tonumber(opts.timestamp_sec) or 0) or nil
  local now = time.now_iso()
  local row, err = db.query_one(
    [[
    INSERT INTO notes (video_id, timestamp_sec, title, content, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?)
    RETURNING *;
  ]],
    { video_id, ts, title, opts.content or "", now, now }
  )
  return row, err
end

--- Get a note by ID.
---@param id integer
---@return table|nil
function M.get(id)
  return db.query_one("SELECT * FROM notes WHERE id = ?;", { id })
end

--- List notes for a video ordered by timestamp (nulls last), then creation time.
---@param video_id string
---@return table[]
function M.list(video_id)
  if not video_id or video_id == "" then
    return {}
  end
  local rows = db.query(
    [[
    SELECT * FROM notes
    WHERE video_id = ?
    ORDER BY
      CASE WHEN timestamp_sec IS NULL THEN 1 ELSE 0 END ASC,
      timestamp_sec ASC,
      id ASC;
  ]],
    { video_id }
  )
  return rows or {}
end

--- Update a note's title, content, or timestamp.
---@param id integer
---@param fields { title?: string, content?: string, timestamp_sec?: number|nil }
---@return boolean, string|nil
function M.update(id, fields)
  local existing = M.get(id)
  if not existing then
    return false, "Note not found"
  end
  local title = fields.title ~= nil and vim.trim(fields.title) or existing.title
  if title == "" then
    title = existing.title
  end
  local content = fields.content ~= nil and fields.content or existing.content
  local ts = existing.timestamp_sec
  if fields.timestamp_sec ~= nil then
    ts = fields.timestamp_sec == false and nil or math.max(0, tonumber(fields.timestamp_sec) or 0)
  end
  return db.exec(
    "UPDATE notes SET title = ?, content = ?, timestamp_sec = ?, updated_at = ? WHERE id = ?;",
    { title, content, ts, time.now_iso(), id }
  )
end

--- Delete a note by ID.
---@param id integer
---@return boolean, string|nil
function M.delete(id)
  return db.exec("DELETE FROM notes WHERE id = ?;", { id })
end

--- Render all notes for a video as Markdown.
---@param video table
---@return string
function M.to_markdown(video)
  local list = M.list(video.id)
  local lines = {
    "# " .. (video.title or video.id),
    "",
    string.format("- **URL:** %s", video.url or ""),
    string.format("- **Category:** %s", video.category or "General"),
    "",
    "## Learning Notes",
    "",
  }
  if #list == 0 then
    table.insert(lines, "_No notes yet._")
  else
    for _, note in ipairs(list) do
      local prefix = note.timestamp_sec ~= nil and ("[" .. time.format(note.timestamp_sec) .. "] ") or ""
      table.insert(lines, string.format("### %s%s", prefix, note.title))
      table.insert(lines, "")
      if note.content and note.content ~= "" then
        for line in (note.content .. "\n"):gmatch("([^\n]*)\n") do
          table.insert(lines, line)
        end
        table.insert(lines, "")
      end
    end
  end
  return table.concat(lines, "\n")
end

return M
