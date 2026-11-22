local config = require("focustube.config")
local db = require("focustube.core.database")
local json = require("focustube.utils.json")
local system = require("focustube.utils.system")
local time = require("focustube.utils.time")

local M = {}

--- Insert or update a video record directly in the local library.
---@param video { id: string, url: string, title: string, channel?: string, duration_sec?: number, category?: string, watch_later?: boolean|integer }
---@return table|nil, string|nil
function M.upsert(video)
  if not video or not video.id or not video.url or not video.title then
    return nil, "Missing required video fields (id, url, title)"
  end
  local now = time.now_iso()
  local existing = M.get(video.id)
  if existing then
    local ok, err = db.exec(
      [[
      UPDATE videos
      SET url = ?, title = ?, channel = ?, duration_sec = ?, category = ?, watch_later = ?, updated_at = ?
      WHERE id = ?;
    ]],
      {
        video.url,
        video.title,
        video.channel or existing.channel or "",
        video.duration_sec or existing.duration_sec or 0,
        video.category or existing.category or "General",
        video.watch_later ~= nil and (video.watch_later and 1 or 0) or existing.watch_later,
        now,
        video.id,
      }
    )
    if not ok then
      return nil, err
    end
    return M.get(video.id), nil
  end

  local ok, err = db.exec(
    [[
    INSERT INTO videos (id, url, title, channel, duration_sec, category, watch_later, position_sec, completed, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, ?, ?);
  ]],
    {
      video.id,
      video.url,
      video.title,
      video.channel or "",
      video.duration_sec or 0,
      video.category or "General",
      (video.watch_later == true or video.watch_later == 1) and 1 or 0,
      now,
      now,
    }
  )
  if not ok then
    return nil, err
  end
  return M.get(video.id), nil
end

--- Fetch metadata from yt-dlp (using Deno JS runtime when available) and save to library.
---@param url string
---@param opts? { category?: string, watch_later?: boolean }
---@param cb fun(video: table|nil, err: string|nil)
function M.add_url(url, opts, cb)
  opts = opts or {}
  local video_id, parse_err = system.parse_youtube_url(url)
  if not video_id then
    cb(nil, parse_err)
    return
  end

  local cfg = config.get()
  local yt_dlp = cfg.binaries.yt_dlp
  if not system.has_executable(yt_dlp) then
    cb(nil, "yt-dlp executable not found: " .. yt_dlp)
    return
  end

  local cmd = {
    yt_dlp,
    "--dump-json",
    "--no-playlist",
    "--no-warnings",
    "--skip-download",
  }
  if system.has_executable(cfg.binaries.deno) then
    table.insert(cmd, "--js-runtimes")
    table.insert(cmd, "deno")
  end
  table.insert(cmd, system.canonical_url(video_id))

  system.run_async(cmd, { timeout = 30000 }, function(res)
    if res.code ~= 0 then
      local msg = res.stderr ~= "" and res.stderr or ("yt-dlp exited with " .. res.code)
      cb(nil, msg)
      return
    end

    local first_line = res.stdout:match("^([^\r\n]+)") or res.stdout
    local meta, dec_err = json.decode(first_line)
    if not meta then
      cb(nil, "Failed to parse yt-dlp metadata: " .. tostring(dec_err))
      return
    end

    local saved, db_err = M.upsert({
      id = video_id,
      url = system.canonical_url(video_id),
      title = meta.title or ("YouTube Video " .. video_id),
      channel = meta.uploader or meta.channel or "",
      duration_sec = tonumber(meta.duration) or 0,
      category = opts.category or "General",
      watch_later = opts.watch_later or false,
    })
    cb(saved, db_err)
  end)
end

--- Get a single video by ID.
---@param video_id string
---@return table|nil
function M.get(video_id)
  if not video_id or video_id == "" then
    return nil
  end
  local row = db.query_one("SELECT * FROM videos WHERE id = ?;", { video_id })
  return row
end

--- Check whether a video ID exists in the approved local library.
---@param video_id string
---@return boolean
function M.is_approved(video_id)
  return M.get(video_id) ~= nil
end

--- List videos with optional filters.
---@param filter? { category?: string, watch_later?: boolean, completed?: boolean, search?: string }
---@return table[]
function M.list(filter)
  filter = filter or {}
  local clauses = {}
  local params = {}

  if filter.category and filter.category ~= "" and filter.category ~= "All" then
    table.insert(clauses, "category = ?")
    table.insert(params, filter.category)
  end
  if filter.watch_later ~= nil then
    table.insert(clauses, "watch_later = ?")
    table.insert(params, filter.watch_later and 1 or 0)
  end
  if filter.completed ~= nil then
    table.insert(clauses, "completed = ?")
    table.insert(params, filter.completed and 1 or 0)
  end
  if filter.search and filter.search ~= "" then
    table.insert(clauses, "(title LIKE ? OR channel LIKE ?)")
    local pat = "%" .. filter.search .. "%"
    table.insert(params, pat)
    table.insert(params, pat)
  end

  local where = #clauses > 0 and ("WHERE " .. table.concat(clauses, " AND ")) or ""
  local sql = string.format(
    "SELECT * FROM videos %s ORDER BY completed ASC, watch_later DESC, updated_at DESC;",
    where
  )
  local rows = db.query(sql, params)
  return rows or {}
end

--- List distinct categories in the library.
---@return string[]
function M.categories()
  local rows = db.query("SELECT DISTINCT category FROM videos ORDER BY category ASC;")
  local cats = { "All" }
  local seen = { All = true }
  for _, r in ipairs(rows or {}) do
    if r.category and not seen[r.category] then
      seen[r.category] = true
      table.insert(cats, r.category)
    end
  end
  return cats
end

--- Set a video's learning category.
---@param video_id string
---@param category string
---@return boolean, string|nil
function M.set_category(video_id, category)
  local cat = vim.trim(category or "")
  if cat == "" then
    cat = "General"
  end
  return db.exec(
    "UPDATE videos SET category = ?, updated_at = ? WHERE id = ?;",
    { cat, time.now_iso(), video_id }
  )
end

--- Toggle watch-later flag for a video.
---@param video_id string
---@return boolean, string|nil
function M.toggle_watch_later(video_id)
  local video = M.get(video_id)
  if not video then
    return false, "Video not found"
  end
  local next_val = (video.watch_later == 1) and 0 or 1
  return db.exec(
    "UPDATE videos SET watch_later = ?, updated_at = ? WHERE id = ?;",
    { next_val, time.now_iso(), video_id }
  )
end

--- Delete a video and its associated bookmarks/notes from the library.
---@param video_id string
---@return boolean, string|nil
function M.delete(video_id)
  return db.exec("DELETE FROM videos WHERE id = ?;", { video_id })
end

--- Summary statistics for the dashboard.
---@return { total: integer, completed: integer, watch_later: integer, in_progress: integer }
function M.stats()
  local row = db.query_one([[
    SELECT
      COUNT(*) AS total,
      SUM(CASE WHEN completed = 1 THEN 1 ELSE 0 END) AS completed,
      SUM(CASE WHEN watch_later = 1 THEN 1 ELSE 0 END) AS watch_later,
      SUM(CASE WHEN completed = 0 AND position_sec > 0 THEN 1 ELSE 0 END) AS in_progress
    FROM videos;
  ]])
  if not row then
    return { total = 0, completed = 0, watch_later = 0, in_progress = 0 }
  end
  return {
    total = tonumber(row.total) or 0,
    completed = tonumber(row.completed) or 0,
    watch_later = tonumber(row.watch_later) or 0,
    in_progress = tonumber(row.in_progress) or 0,
  }
end

return M
