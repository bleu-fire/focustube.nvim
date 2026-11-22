-- Headless test runner for FocusTube.nvim
-- Run with: nvim --headless -u NONE -l tests/run.lua

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.runtimepath:prepend(root)

local passed = 0
local failed = 0

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", msg or "assertion failed", vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

local function assert_true(val, msg)
  if not val then
    error(msg or "expected truthy value", 2)
  end
end

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    io.write(string.format("PASS  %s\n", name))
  else
    failed = failed + 1
    io.write(string.format("FAIL  %s\n      %s\n", name, tostring(err)))
  end
end

-- Setup isolated temporary SQLite database
local tmp_db = vim.fn.tempname() .. ".db"
local focustube = require("focustube")
focustube.setup({
  db_path = tmp_db,
  progress = { save_interval_ms = 60000, completion_threshold = 0.90, resume_margin_sec = 5 },
})

local time = require("focustube.utils.time")
local system = require("focustube.utils.system")
local db = require("focustube.core.database")
local library = require("focustube.core.library")
local progress = require("focustube.core.progress")
local bookmarks = require("focustube.core.bookmarks")
local notes = require("focustube.core.notes")
local focus = require("focustube.core.focus")
local ipc = require("focustube.core.ipc")
local player = require("focustube.core.player")
local paths = require("focustube.utils.paths")

test("time.format and time.parse", function()
  assert_eq(time.format(0), "00:00", "0s")
  assert_eq(time.format(500), "08:20", "500s")
  assert_eq(time.format(3661), "01:01:01", "3661s")
  assert_eq(time.parse("08:20"), 500, "parse MM:SS")
  assert_eq(time.parse("01:01:01"), 3661, "parse HH:MM:SS")
  assert_eq(time.parse("42"), 42, "parse SS")
  assert_eq(time.parse("bad"), nil, "parse invalid")
  assert_true(time.progress_bar(50, 100, 10):match("50%%") ~= nil, "progress bar 50%")
end)

test("system.parse_youtube_url validation", function()
  local id1 = system.parse_youtube_url("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10s")
  assert_eq(id1, "dQw4w9WgXcQ", "standard watch URL")

  local id2 = system.parse_youtube_url("https://youtu.be/abc123XYZ_-")
  assert_eq(id2, "abc123XYZ_-", "youtu.be URL")

  local id3 = system.parse_youtube_url("https://www.youtube.com/live/liveVid123")
  assert_eq(id3, "liveVid123", "live URL")

  local bad_shorts, err_shorts = system.parse_youtube_url("https://www.youtube.com/shorts/short12345")
  assert_eq(bad_shorts, nil, "shorts blocked")
  assert_true(err_shorts:match("Shorts") ~= nil, "shorts error message")

  local bad_host = system.parse_youtube_url("https://vimeo.com/123456")
  assert_eq(bad_host, nil, "non-youtube rejected")
end)

test("library CRUD, categories, watch_later, and SQL quoting", function()
  local v1, err1 = library.upsert({
    id = "vid_neovim_01",
    url = "https://www.youtube.com/watch?v=vid_neovim_01",
    title = "Neovim 'LSP' & Treesitter Setup",
    channel = "Dev Channel",
    duration_sec = 1800,
    category = "Neovim",
    watch_later = true,
  })
  assert_eq(err1, nil, "upsert v1 err")
  assert_eq(v1.title, "Neovim 'LSP' & Treesitter Setup", "quotes preserved")
  assert_eq(v1.watch_later, 1, "watch_later set")
  assert_true(library.is_approved("vid_neovim_01"), "approved check")
  assert_eq(library.is_approved("unknown_vid"), false, "unapproved check")

  library.upsert({
    id = "vid_lua_02",
    url = "https://www.youtube.com/watch?v=vid_lua_02",
    title = "Lua Coroutines Deep Dive",
    channel = "Lua Lab",
    duration_sec = 1200,
    category = "Lua",
    watch_later = false,
  })

  assert_eq(#library.list({ category = "Neovim" }), 1, "filter by category")
  assert_eq(#library.list({ watch_later = true }), 1, "filter by watch_later")
  assert_eq(#library.list({ search = "Coroutines" }), 1, "filter by search")

  library.toggle_watch_later("vid_lua_02")
  assert_eq(#library.list({ watch_later = true }), 2, "toggled watch_later")

  local stats = library.stats()
  assert_eq(stats.total, 2, "stats total")
end)

test("progress tracking, resume position, and completion", function()
  progress.save("vid_neovim_01", 600, 1800)
  local v = library.get("vid_neovim_01")
  assert_eq(v.position_sec, 600, "saved position")
  assert_eq(v.completed, 0, "not yet completed")
  assert_eq(progress.get_resume_position(v), 600, "resume at 600")

  progress.save("vid_neovim_01", 1700, 1800) -- 94.4% >= 90%
  v = library.get("vid_neovim_01")
  assert_eq(v.completed, 1, "marked completed at >=90%")
  assert_eq(progress.get_resume_position(v), 0, "completed video resumes at 0")
end)

test("bookmarks CRUD and ordering", function()
  local b1 = bookmarks.add("vid_neovim_01", 754, "Treesitter setup")
  local b2 = bookmarks.add("vid_neovim_01", 500, "Mason configuration")
  assert_true(b1 ~= nil and b2 ~= nil, "bookmarks created")

  local list = bookmarks.list("vid_neovim_01")
  assert_eq(#list, 2, "2 bookmarks")
  assert_eq(bookmarks.format_line(list[1]), "08:20 — Mason configuration", "ordered first")
  assert_eq(bookmarks.format_line(list[2]), "12:34 — Treesitter setup", "ordered second")

  bookmarks.update(list[1].id, { title = "Mason.nvim setup" })
  assert_eq(bookmarks.list("vid_neovim_01")[1].title, "Mason.nvim setup", "bookmark renamed")

  bookmarks.delete(list[2].id)
  assert_eq(#bookmarks.list("vid_neovim_01"), 1, "bookmark deleted")
end)

test("notes CRUD and markdown export", function()
  local n1 = notes.create("vid_neovim_01", {
    title = "Keymaps",
    timestamp_sec = 500,
    content = "Use vim.keymap.set for buffer-local maps.",
  })
  assert_true(n1 ~= nil, "note created")

  notes.update(n1.id, { content = "Updated markdown content." })
  local fetched = notes.get(n1.id)
  assert_eq(fetched.content, "Updated markdown content.", "note updated")

  local v = library.get("vid_neovim_01")
  local md = notes.to_markdown(v)
  assert_true(md:match("## Learning Notes") ~= nil, "markdown header")
  assert_true(md:match("%[08:20%] Keymaps") ~= nil, "markdown timestamped note")

  notes.delete(n1.id)
  assert_eq(#notes.list("vid_neovim_01"), 0, "note deleted")
end)

test("focus mode locks browsing and switching", function()
  local ok_bad = focus.enable("not_in_library")
  assert_eq(ok_bad, false, "cannot focus unapproved video")

  local ok, err = focus.enable("vid_neovim_01")
  assert_eq(ok, true, "focus enabled: " .. tostring(err))
  assert_eq(focus.is_active(), true, "focus active")
  assert_eq(focus.can_browse(), false, "browsing blocked in focus mode")
  assert_eq(focus.can_switch_video("vid_lua_02"), false, "switching blocked")
  assert_eq(focus.can_switch_video("vid_neovim_01"), true, "same video allowed")

  local play_ok, play_err = player.play("vid_lua_02")
  assert_eq(play_ok, false, "player refuses switching during focus mode")
  assert_true(play_err:match("Focus Mode") ~= nil, "focus mode error")

  focus.disable()
  assert_eq(focus.is_active(), false, "focus disabled")
  assert_eq(focus.can_browse(), true, "browsing restored")
end)

test("ipc Unix domain socket JSON command/response and events", function()
  local sock_path = paths.ipc_socket_path()
  paths.remove_file(sock_path)

  local server = vim.uv.new_pipe(false)
  assert_true(server ~= nil, "create server pipe")
  local bind_ok, bind_err = server:bind(sock_path)
  assert_true(bind_ok, "bind unix socket: " .. tostring(bind_err))

  local server_client = nil
  server:listen(1, function(listen_err)
    assert_eq(listen_err, nil, "listen err")
    server_client = vim.uv.new_pipe(false)
    server:accept(server_client)
    server_client:read_start(function(_, chunk)
      if not chunk then
        return
      end
      for line in chunk:gmatch("([^\n]+)") do
        local req = vim.json.decode(line)
        local resp = vim.json.encode({ request_id = req.request_id, data = 42, error = "success" }) .. "\n"
        server_client:write(resp)
        server_client:write(vim.json.encode({ event = "property-change", name = "time-pos", data = 123.5 }) .. "\n")
      end
    end)
  end)

  local got_response = nil
  local got_event = nil
  local client = ipc.new(sock_path, {
    on_event = function(msg)
      got_event = msg
    end,
  })

  local connected = false
  client:connect(function(ok)
    connected = ok
    if ok then
      client:send({ "get_property", "time-pos" }, function(res)
        got_response = res
      end)
    end
  end)

  local done = vim.wait(2000, function()
    return connected and got_response ~= nil and got_event ~= nil
  end, 20)

  client:close()
  if server_client and not server_client:is_closing() then
    server_client:close()
  end
  if not server:is_closing() then
    server:close()
  end
  paths.remove_file(sock_path)

  assert_true(done, "IPC roundtrip completed")
  assert_eq(got_response.data, 42, "response data")
  assert_eq(got_event.name, "time-pos", "event name")
  assert_eq(got_event.data, 123.5, "event data")
end)

test("user commands registered", function()
  local cmds = vim.api.nvim_get_commands({})
  assert_true(cmds.FocusTube ~= nil, "FocusTube command")
  assert_true(cmds.FocusTubeLibrary ~= nil, "FocusTubeLibrary command")
  assert_true(cmds.FocusTubeAdd ~= nil, "FocusTubeAdd command")
  assert_true(cmds.FocusTubeFocus ~= nil, "FocusTubeFocus command")
  assert_true(cmds.FocusTubeHealth ~= nil, "FocusTubeHealth command")
end)

-- Cleanup temp database
db.reset()
paths.remove_file(tmp_db)
paths.remove_file(tmp_db .. "-wal")
paths.remove_file(tmp_db .. "-shm")

io.write(string.format("\nResults: %d passed, %d failed\n", passed, failed))
if failed > 0 then
  os.exit(1)
end
os.exit(0)
