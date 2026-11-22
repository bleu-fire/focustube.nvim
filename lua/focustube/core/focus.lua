local config = require("focustube.config")
local db = require("focustube.core.database")
local library = require("focustube.core.library")
local time = require("focustube.utils.time")

local M = {}

M._state = {
  active = false,
  video_id = nil,
  session_id = nil,
  started_at = nil,
  started_epoch = nil,
}

--- Check whether Focus Mode is currently active.
---@return boolean
function M.is_active()
  return M._state.active
end

--- Return current Focus Mode status table.
---@return { active: boolean, video_id: string|nil, session_id: integer|nil, started_at: string|nil, elapsed_sec: number }
function M.status()
  local elapsed = 0
  if M._state.active and M._state.started_epoch then
    elapsed = math.max(0, os.time() - M._state.started_epoch)
  end
  return {
    active = M._state.active,
    video_id = M._state.video_id,
    session_id = M._state.session_id,
    started_at = M._state.started_at,
    elapsed_sec = elapsed,
  }
end

--- Enable Focus Mode locked to a specific approved video.
---@param video_id string
---@return boolean, string|nil
function M.enable(video_id)
  if not video_id or video_id == "" then
    return false, "Select an approved library video to start Focus Mode"
  end
  if not library.is_approved(video_id) then
    return false, "Cannot start Focus Mode: video is not in your library"
  end

  if M._state.active and M._state.video_id == video_id then
    return true, nil
  end
  if M._state.active then
    M.disable()
  end

  local now = time.now_iso()
  local row, err = db.query_one(
    [[
    INSERT INTO focus_sessions (video_id, started_at)
    VALUES (?, ?)
    RETURNING id;
  ]],
    { video_id, now }
  )
  if err then
    return false, err
  end

  M._state.active = true
  M._state.video_id = video_id
  M._state.session_id = row and row.id or nil
  M._state.started_at = now
  M._state.started_epoch = os.time()

  return true, nil
end

--- Disable Focus Mode and record session duration.
---@return boolean
function M.disable()
  if not M._state.active then
    return false
  end

  local elapsed = M._state.started_epoch and math.max(0, os.time() - M._state.started_epoch) or 0
  if M._state.session_id then
    db.exec(
      "UPDATE focus_sessions SET ended_at = ?, duration_sec = ? WHERE id = ?;",
      { time.now_iso(), elapsed, M._state.session_id }
    )
  end

  M._state.active = false
  M._state.video_id = nil
  M._state.session_id = nil
  M._state.started_at = nil
  M._state.started_epoch = nil
  return true
end

--- Toggle Focus Mode for a given video (or disable if already active).
---@param video_id? string
---@return boolean, string|nil
function M.toggle(video_id)
  if M._state.active then
    M.disable()
    return true, nil
  end
  return M.enable(video_id or "")
end

--- Whether library browsing is allowed right now.
---@return boolean
function M.can_browse()
  if not M._state.active then
    return true
  end
  return not config.get().focus.block_browsing
end

--- Whether switching to target_video_id is allowed right now.
---@param target_video_id string
---@return boolean
function M.can_switch_video(target_video_id)
  if not M._state.active then
    return true
  end
  return M._state.video_id == target_video_id
end

return M
