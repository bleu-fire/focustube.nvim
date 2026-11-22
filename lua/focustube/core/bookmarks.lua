local db = require("focustube.core.database")
local time = require("focustube.utils.time")

local M = {}

--- Add a timestamp bookmark for a video.
---@param video_id string
---@param timestamp_sec number
---@param title string
---@return table|nil, string|nil
function M.add(video_id, timestamp_sec, title)
  if not video_id or video_id == "" then
    return nil, "Invalid video_id"
  end
  local ts = math.max(0, tonumber(timestamp_sec) or 0)
  local clean_title = vim.trim(title or "")
  if clean_title == "" then
    clean_title = "Bookmark at " .. time.format(ts)
  end
  local now = time.now_iso()
  local row, err = db.query_one(
    [[
    INSERT INTO bookmarks (video_id, timestamp_sec, title, created_at)
    VALUES (?, ?, ?, ?)
    RETURNING *;
  ]],
    { video_id, ts, clean_title, now }
  )
  return row, err
end

--- List bookmarks for a video ordered by timestamp ascending.
---@param video_id string
---@return table[]
function M.list(video_id)
  if not video_id or video_id == "" then
    return {}
  end
  local rows = db.query(
    "SELECT * FROM bookmarks WHERE video_id = ? ORDER BY timestamp_sec ASC, id ASC;",
    { video_id }
  )
  return rows or {}
end

--- Update a bookmark's title or timestamp.
---@param id integer
---@param fields { title?: string, timestamp_sec?: number }
---@return boolean, string|nil
function M.update(id, fields)
  local existing = db.query_one("SELECT * FROM bookmarks WHERE id = ?;", { id })
  if not existing then
    return false, "Bookmark not found"
  end
  local title = fields.title and vim.trim(fields.title) or existing.title
  if title == "" then
    title = existing.title
  end
  local ts = fields.timestamp_sec ~= nil and math.max(0, tonumber(fields.timestamp_sec) or 0)
    or existing.timestamp_sec
  return db.exec("UPDATE bookmarks SET title = ?, timestamp_sec = ? WHERE id = ?;", { title, ts, id })
end

--- Delete a bookmark by ID.
---@param id integer
---@return boolean, string|nil
function M.delete(id)
  return db.exec("DELETE FROM bookmarks WHERE id = ?;", { id })
end

--- Format a bookmark line for display.
---@param bookmark table
---@return string
function M.format_line(bookmark)
  return string.format("%s — %s", time.format(bookmark.timestamp_sec), bookmark.title)
end

return M
