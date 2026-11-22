local config = require("focustube.config")
local db = require("focustube.core.database")
local time = require("focustube.utils.time")

local M = {}

M._state = {
  video_id = nil,
  position_sec = 0,
  duration_sec = 0,
  dirty = false,
  timer = nil,
}

--- Compute whether a video should be marked completed based on position & duration.
---@param position_sec number
---@param duration_sec number
---@return boolean
function M.should_mark_completed(position_sec, duration_sec)
  if not duration_sec or duration_sec <= 0 then
    return false
  end
  local threshold = config.get().progress.completion_threshold or 0.90
  return (position_sec / duration_sec) >= threshold
end

--- Determine safe resume position for a video.
---@param video table
---@return number
function M.get_resume_position(video)
  if not video then
    return 0
  end
  if video.completed == 1 then
    return 0
  end
  local pos = tonumber(video.position_sec) or 0
  local dur = tonumber(video.duration_sec) or 0
  local margin = config.get().progress.resume_margin_sec or 5
  if dur > 0 and pos >= math.max(0, dur - margin) then
    return 0
  end
  return math.max(0, pos)
end

--- Persist progress for a video directly.
---@param video_id string
---@param position_sec number
---@param duration_sec? number
---@return boolean, string|nil
function M.save(video_id, position_sec, duration_sec)
  if not video_id or video_id == "" then
    return false, "Invalid video_id"
  end
  local pos = math.max(0, tonumber(position_sec) or 0)
  local dur = tonumber(duration_sec) or 0
  local now = time.now_iso()

  if dur > 0 then
    local completed = M.should_mark_completed(pos, dur) and 1 or 0
    return db.exec(
      [[
      UPDATE videos
      SET position_sec = ?,
          duration_sec = ?,
          completed = CASE WHEN completed = 1 THEN 1 ELSE ? END,
          last_watched_at = ?,
          updated_at = ?
      WHERE id = ?;
    ]],
      { pos, dur, completed, now, now, video_id }
    )
  end

  return db.exec(
    [[
    UPDATE videos
    SET position_sec = ?,
        last_watched_at = ?,
        updated_at = ?
    WHERE id = ?;
  ]],
    { pos, now, now, video_id }
  )
end

--- Mark a video completed or incomplete explicitly.
---@param video_id string
---@param completed boolean
---@return boolean, string|nil
function M.mark_completed(video_id, completed)
  return db.exec(
    "UPDATE videos SET completed = ?, updated_at = ? WHERE id = ?;",
    { completed and 1 or 0, time.now_iso(), video_id }
  )
end

--- Start periodic progress tracking for an active playback session.
---@param video_id string
---@param initial_pos? number
---@param duration_sec? number
function M.start_tracking(video_id, initial_pos, duration_sec)
  M.stop_tracking()
  M._state.video_id = video_id
  M._state.position_sec = initial_pos or 0
  M._state.duration_sec = duration_sec or 0
  M._state.dirty = false

  local interval = config.get().progress.save_interval_ms or 5000
  local timer = vim.uv.new_timer()
  if timer then
    M._state.timer = timer
    timer:start(interval, interval, function()
      if M._state.dirty and M._state.video_id then
        vim.schedule(function()
          M.flush()
        end)
      end
    end)
  end
end

--- Update in-memory playback position/duration.
---@param position_sec? number
---@param duration_sec? number
function M.update(position_sec, duration_sec)
  if not M._state.video_id then
    return
  end
  if position_sec ~= nil then
    M._state.position_sec = math.max(0, position_sec)
    M._state.dirty = true
  end
  if duration_sec ~= nil and duration_sec > 0 then
    M._state.duration_sec = duration_sec
    M._state.dirty = true
  end
end

--- Flush current in-memory progress to SQLite.
function M.flush()
  if not M._state.video_id then
    return
  end
  M.save(M._state.video_id, M._state.position_sec, M._state.duration_sec)
  M._state.dirty = false
end

--- Flush and stop periodic tracking timer.
function M.stop_tracking()
  if M._state.video_id then
    M.flush()
  end
  if M._state.timer then
    if not M._state.timer:is_closing() then
      M._state.timer:stop()
      M._state.timer:close()
    end
    M._state.timer = nil
  end
  M._state.video_id = nil
  M._state.position_sec = 0
  M._state.duration_sec = 0
  M._state.dirty = false
end

return M
