local M = {}

--- Format seconds into HH:MM:SS or MM:SS.
---@param seconds number|nil
---@return string
function M.format(seconds)
  if not seconds or type(seconds) ~= "number" or seconds < 0 then
    return "00:00"
  end
  local total = math.floor(seconds + 0.5)
  local hours = math.floor(total / 3600)
  local mins = math.floor((total % 3600) / 60)
  local secs = total % 60
  if hours > 0 then
    return string.format("%02d:%02d:%02d", hours, mins, secs)
  end
  return string.format("%02d:%02d", mins, secs)
end

--- Parse a timestamp string (SS, MM:SS, or HH:MM:SS) into seconds.
---@param str string|number
---@return number|nil
function M.parse(str)
  if type(str) == "number" then
    return str >= 0 and str or nil
  end
  if type(str) ~= "string" then
    return nil
  end
  local trimmed = vim.trim(str)
  if trimmed == "" then
    return nil
  end
  if trimmed:match("^%d+%.?%d*$") then
    return tonumber(trimmed)
  end
  local parts = {}
  for part in trimmed:gmatch("[^:]+") do
    if not part:match("^%d+%.?%d*$") then
      return nil
    end
    table.insert(parts, tonumber(part))
  end
  if #parts == 2 then
    return parts[1] * 60 + parts[2]
  elseif #parts == 3 then
    return parts[1] * 3600 + parts[2] * 60 + parts[3]
  end
  return nil
end

--- Return current UTC ISO-8601 timestamp.
---@return string
function M.now_iso()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

--- Format a progress bar string.
---@param position number
---@param duration number
---@param width? integer
---@return string
function M.progress_bar(position, duration, width)
  width = width or 24
  if not duration or duration <= 0 then
    return "[" .. string.rep("░", width) .. "] 0%"
  end
  local ratio = math.max(0, math.min(1, (position or 0) / duration))
  local filled = math.floor(ratio * width + 0.5)
  local empty = width - filled
  local pct = math.floor(ratio * 100 + 0.5)
  return string.format("[%s%s] %d%%", string.rep("█", filled), string.rep("░", empty), pct)
end

return M
