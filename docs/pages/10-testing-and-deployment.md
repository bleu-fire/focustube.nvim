# Page 10: Verification, Testing, and Deployment

## 10.1 Headless Test Harness

`tests/run.lua` executes inside Neovim without external test frameworks:

```bash
nvim --headless -u NONE -l tests/run.lua
```

Each run initializes an isolated temporary SQLite database and verifies:
1. Time formatting, timestamp parsing (`SS`, `MM:SS`, `HH:MM:SS`), and progress bar rendering.
2. YouTube URL validation, ID extraction, and Shorts/non-YouTube rejection.
3. Library CRUD, category/watch-later filtering, and SQL single-quote escaping.
4. Progress persistence, 90% completion threshold logic, and resume clamping.
5. Bookmark ordering, renaming, and deletion.
6. Note creation, updates, deletion, and Markdown export.
7. Focus Mode browsing locks, video-switching blocks, and session logging.
8. Live Unix domain socket IPC roundtrip using an in-process `vim.uv.new_pipe(false)` server to verify JSON command/response correlation and `property-change` event delivery.
9. User command registration.

## 10.2 `lazy.nvim` Integration and Health Checks

`plugin/focustube.lua` registers `:FocusTube` lazily before `setup()` runs. In `lazy.nvim`, the plugin configures via `opts = {}` and exposes `:FocusTubeHealth` to verify runtime availability of `mpv`, `yt-dlp`, `deno`, and `sqlite3`.

---
[Previous: Page 09](./09-focus-mode-enforcement.md) | [Index](./README.md)
