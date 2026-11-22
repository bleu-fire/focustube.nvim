local config = require("focustube.config")
local json = require("focustube.utils.json")
local paths = require("focustube.utils.paths")
local system = require("focustube.utils.system")

local M = {}

---@type string|nil
M._db_path = nil
M._initialized = false

--- Escape and quote a Lua value for SQLite SQL literals.
---@param val any
---@return string
function M.quote(val)
  if val == nil or val == vim.NIL then
    return "NULL"
  end
  local t = type(val)
  if t == "boolean" then
    return val and "1" or "0"
  elseif t == "number" then
    if val ~= val or val == math.huge or val == -math.huge then
      return "NULL"
    end
    return tostring(val)
  else
    local s = tostring(val):gsub("'", "''")
    return "'" .. s .. "'"
  end
end

--- Bind positional `?` parameters into a SQL template safely.
---@param sql string
---@param params? any[]
---@return string
function M.bind(sql, params)
  if not params or #params == 0 then
    return sql
  end
  local idx = 0
  local out = sql:gsub("%?", function()
    idx = idx + 1
    return M.quote(params[idx])
  end)
  return out
end

--- Return the active database path.
---@return string
function M.get_path()
  if not M._db_path then
    M._db_path = paths.db_path(config.get().db_path)
  end
  return M._db_path
end

--- Reset database state (useful for tests or switching DB path).
---@param custom_path? string
function M.reset(custom_path)
  M._db_path = custom_path and paths.db_path(custom_path) or nil
  M._initialized = false
end

--- Execute raw SQL statements (no JSON output expected).
---@param sql string
---@param params? any[]
---@return boolean, string|nil
function M.exec(sql, params)
  M.init()
  local bin = config.get().binaries.sqlite3
  local bound = M.bind(sql, params)
  local res = system.run_sync({
    bin,
    "-batch",
    "-cmd",
    ".timeout 5000",
    "-cmd",
    "PRAGMA foreign_keys=ON;",
    M.get_path(),
    bound,
  })
  if res.code ~= 0 then
    return false, res.stderr ~= "" and res.stderr or ("sqlite3 exited with " .. res.code)
  end
  return true, nil
end

--- Execute a query and return decoded JSON rows.
---@param sql string
---@param params? any[]
---@return table[]|nil, string|nil
function M.query(sql, params)
  M.init()
  local bin = config.get().binaries.sqlite3
  local bound = M.bind(sql, params)
  local res = system.run_sync({
    bin,
    "-batch",
    "-json",
    "-cmd",
    ".timeout 5000",
    "-cmd",
    "PRAGMA foreign_keys=ON;",
    M.get_path(),
    bound,
  })
  if res.code ~= 0 then
    return nil, res.stderr ~= "" and res.stderr or ("sqlite3 exited with " .. res.code)
  end
  local out = vim.trim(res.stdout)
  if out == "" then
    return {}, nil
  end
  local decoded, err = json.decode(out)
  if err then
    return nil, err
  end
  return decoded or {}, nil
end

--- Execute a query and return the first row or nil.
---@param sql string
---@param params? any[]
---@return table|nil, string|nil
function M.query_one(sql, params)
  local rows, err = M.query(sql, params)
  if err then
    return nil, err
  end
  return rows and rows[1] or nil, nil
end

--- Initialize SQLite schema if not already initialized.
---@return boolean, string|nil
function M.init()
  if M._initialized then
    return true, nil
  end
  local bin = config.get().binaries.sqlite3
  if not system.has_executable(bin) then
    return false, "sqlite3 executable not found: " .. bin
  end

  local schema = [[
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;
PRAGMA busy_timeout=5000;

CREATE TABLE IF NOT EXISTS videos (
  id TEXT PRIMARY KEY,
  url TEXT NOT NULL,
  title TEXT NOT NULL,
  channel TEXT DEFAULT '',
  duration_sec REAL DEFAULT 0,
  category TEXT NOT NULL DEFAULT 'General',
  watch_later INTEGER NOT NULL DEFAULT 0,
  position_sec REAL NOT NULL DEFAULT 0,
  completed INTEGER NOT NULL DEFAULT 0,
  last_watched_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS bookmarks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  video_id TEXT NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
  timestamp_sec REAL NOT NULL,
  title TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_bookmarks_video_ts
  ON bookmarks(video_id, timestamp_sec);

CREATE TABLE IF NOT EXISTS notes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  video_id TEXT NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
  timestamp_sec REAL,
  title TEXT NOT NULL,
  content TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_notes_video_ts
  ON notes(video_id, timestamp_sec);

CREATE TABLE IF NOT EXISTS focus_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  video_id TEXT NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
  started_at TEXT NOT NULL,
  ended_at TEXT,
  duration_sec REAL NOT NULL DEFAULT 0
);
]]

  local res = system.run_sync({ bin, "-batch", M.get_path(), schema })
  if res.code ~= 0 then
    return false, res.stderr ~= "" and res.stderr or "Failed to initialize SQLite schema"
  end
  M._initialized = true
  return true, nil
end

return M
