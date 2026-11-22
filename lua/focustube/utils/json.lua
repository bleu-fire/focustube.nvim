local M = {}

--- Encode a Lua value to a JSON string.
---@param val any
---@return string
function M.encode(val)
  return vim.json.encode(val)
end

--- Decode a JSON string safely without throwing.
---@param str string
---@return any|nil, string|nil
function M.decode(str)
  if type(str) ~= "string" or str == "" then
    return nil, "empty json input"
  end
  local ok, result = pcall(vim.json.decode, str)
  if not ok then
    return nil, tostring(result)
  end
  return result, nil
end

return M
