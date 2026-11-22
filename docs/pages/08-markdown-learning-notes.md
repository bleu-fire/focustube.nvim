# Page 08: Markdown Learning Notes and Buffer Persistence

## 8.1 Data Model and Sorting

`core/notes.lua` associates Markdown notes with a `video_id` and an optional `timestamp_sec`. Listing queries sort timestamped notes chronologically first, followed by general notes without timestamps:

```sql
ORDER BY
  CASE WHEN timestamp_sec IS NULL THEN 1 ELSE 0 END ASC,
  timestamp_sec ASC,
  id ASC;
```

## 8.2 Native `acwrite` Floating Editor

Instead of a single-line prompt for note bodies, `ui/notes.open_editor` creates a scratch Neovim buffer with:
- `buftype = "acwrite"`
- `filetype = "markdown"`
- Virtual buffer name `focustube://note/<id>/<title>.md`

A buffer-local `BufWriteCmd` autocmd intercepts `:w` (and `<C-s>`), reads lines from the buffer, writes the updated `content` to SQLite via `notes.update`, and clears `vim.bo[buf].modified`. Pressing `q` auto-saves if modified before closing the floating window.

## 8.3 Consolidated Markdown Export

`notes.to_markdown(video)` compiles the video title, URL, category, and all associated notes (with `[MM:SS]` headings where present) into a standalone Markdown document opened in a new tab via `x` in `ui/notes.lua`.

---
[Previous: Page 07](./07-timestamp-bookmarks.md) | [Index](./README.md) | [Next: Page 09](./09-focus-mode-enforcement.md)
