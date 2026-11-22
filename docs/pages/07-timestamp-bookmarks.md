# Page 07: Timestamp Bookmarks and Temporal Seeking

## 7.1 Capturing Live Playback Coordinates

`core/bookmarks.lua` stores user-defined temporal markers in the `bookmarks` table, indexed by `(video_id, timestamp_sec)`.

When triggered via `b` in the Video Workspace, `a` in the Bookmarks window, or `:FocusTubeBookmark`, FocusTube reads `player.get_state().position_sec` if the target video is currently active in `mpv`, or falls back to the persisted `video.position_sec` when stopped. If the user omits a title, a default label (`Bookmark at MM:SS`) is generated.

## 7.2 Chronological Ordering and Formatting

Queries return bookmarks sorted chronologically (`ORDER BY timestamp_sec ASC, id ASC`). `bookmarks.format_line` renders each entry using `utils/time.format`:

```
08:20 — Mason configuration
12:34 — Treesitter setup
18:42 — LSP configuration
```

## 7.3 Direct Timestamp Jumping

Pressing `<CR>` on a bookmark in `ui/bookmarks.lua` branches on player state:
- **Active in `mpv`**: Sends `{ "seek", timestamp_sec, "absolute" }` over IPC, updates in-memory position, and flushes progress.
- **Inactive**: Launches `mpv` with `start_sec = timestamp_sec`.

---
[Previous: Page 06](./06-progress-and-crash-resilience.md) | [Index](./README.md) | [Next: Page 08](./08-markdown-learning-notes.md)
