local M = {}

--- Check if an executable exists on PATH or as an explicit path.
---@param bin string
---@return boolean
function M.has_executable(bin)
  return vim.fn.executable(bin) == 1
end

--- Run a command synchronously using vim.system.
---@param cmd string[]
---@param opts? table
---@return { code: integer, stdout: string, stderr: string }
function M.run_sync(cmd, opts)
  opts = opts or {}
  local res = vim.system(cmd, {
    text = true,
    timeout = opts.timeout or 15000,
    env = opts.env,
  }):wait()
  return {
    code = res.code or -1,
    stdout = res.stdout or "",
    stderr = res.stderr or "",
  }
end

--- Run a command asynchronously using vim.system.
---@param cmd string[]
---@param opts? table
---@param on_exit fun(res: { code: integer, stdout: string, stderr: string })
---@return vim.SystemObj
function M.run_async(cmd, opts, on_exit)
  opts = opts or {}
  return vim.system(cmd, {
    text = true,
    timeout = opts.timeout,
    env = opts.env,
  }, function(res)
    vim.schedule(function()
      on_exit({
        code = res.code or -1,
        stdout = res.stdout or "",
        stderr = res.stderr or "",
      })
    end)
  end)
end

--- Validate and extract a YouTube video ID from a URL.
--- Rejects Shorts, playlists without a video ID, and non-YouTube URLs.
---@param url string
---@return string|nil, string|nil
function M.parse_youtube_url(url)
  if type(url) ~= "string" then
    return nil, "URL must be a string"
  end
  local trimmed = vim.trim(url)
  if trimmed == "" then
    return nil, "URL cannot be empty"
  end

  if trimmed:match("youtube%.com/shorts/") then
    return nil, "YouTube Shorts are blocked in FocusTube"
  end

  local host_ok = trimmed:match("^https?://[%w%.%-]*youtube%.com/")
    or trimmed:match("^https?://youtu%.be/")
    or trimmed:match("^https?://[%w%.%-]*youtube%-nocookie%.com/")

  if not host_ok then
    return nil, "URL must be a valid YouTube video URL"
  end

  -- Watch URL: ?v=VIDEO_ID or &v=VIDEO_ID
  local id = trimmed:match("[?&]v=([%w_%-][%w_%-]+)")
  if not id then
    -- Short URL: youtu.be/VIDEO_ID
    id = trimmed:match("youtu%.be/([%w_%-]+)")
  end
  if not id then
    -- Live or embed URL: youtube.com/live/VIDEO_ID or /embed/VIDEO_ID
    id = trimmed:match("youtube%.com/live/([%w_%-]+)")
      or trimmed:match("youtube%.com/embed/([%w_%-]+)")
  end

  if not id or #id < 6 then
    return nil, "Could not extract a valid YouTube video ID"
  end

  return id, nil
end

--- Canonical watch URL for a YouTube video ID.
---@param video_id string
---@return string
function M.canonical_url(video_id)
  return "https://www.youtube.com/watch?v=" .. video_id
end

return M
