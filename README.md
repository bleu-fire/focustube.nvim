# FocusTube.nvim

An ADHD-friendly, distraction-minimized YouTube learning workflow for Neovim.

FocusTube helps you watch educational videos intentionally without falling into YouTube recommendations, Shorts, or endless browsing. You curate an approved local library, and FocusTube launches `mpv` over a local Unix domain socket while Neovim manages playback progress, timestamp bookmarks, Markdown learning notes, and Focus Mode.

## Requirements

- **Neovim** >= 0.10.0
- **mpv** (external video player with JSON IPC)
- **yt-dlp** (video metadata extraction)
- **Deno** (JavaScript runtime for `yt-dlp`)
- **sqlite3** (local persistence)

## Installation (`lazy.nvim`)

```lua
{
  dir = "~/focustube.nvim", -- or your repository path
  cmd = {
    "FocusTube",
    "FocusTubeLibrary",
    "FocusTubeAdd",
    "FocusTubeFocus",
    "FocusTubeHealth",
  },
  keys = {
    { "<leader>ftd", "<cmd>FocusTube<cr>", desc = "FocusTube Dashboard" },
    { "<leader>ftl", "<cmd>FocusTubeLibrary<cr>", desc = "FocusTube Library" },
    { "<leader>fta", "<cmd>FocusTubeAdd<cr>", desc = "FocusTube Add URL" },
    { "<leader>ftf", "<cmd>FocusTubeFocus<cr>", desc = "FocusTube Focus Mode" },
  },
  opts = {
    player = {
      seek_step = 10,
    },
    progress = {
      save_interval_ms = 5000,
      completion_threshold = 0.90,
    },
  },
}
```

## Features

- **Approved Video Library**: Add YouTube URLs manually, validate them (Shorts blocked), fetch title & duration via `yt-dlp`, organize by category, and manage a Watch Later queue.
- **External `mpv` Player via JSON IPC**: Launches `mpv` with a unique per-session Unix domain socket (`--input-ipc-server`), never over TCP/network. Supports play, pause/resume, relative/absolute seek, stop, crash-safe socket cleanup, and automatic exit detection.
- **Crash-Resilient Progress Tracking**: Saves playback position periodically, on pause, and on exit in SQLite WAL mode. Automatically resumes where you left off and marks videos completed at 90% (configurable).
- **Timestamp Bookmarks**: Capture timestamps while watching (e.g., `08:20 — Mason configuration`) and jump directly to them in `mpv`.
- **Markdown Learning Notes**: Create, edit, and export per-video notes with optional timestamps in a floating Markdown editor.
- **Focus Mode**: Locks the UI onto one selected video, hides library browsing and Watch Later queues, and prevents accidental video switching.

## Running Tests

```bash
nvim --headless -u NONE -l tests/run.lua
```
