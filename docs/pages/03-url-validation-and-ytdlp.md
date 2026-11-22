# Page 03: URL Validation and Metadata Extraction

## 3.1 Strict URL Grammar

`utils/system.lua` implements `parse_youtube_url(url)` to validate user input before any external process runs:

- **Allowed Hosts**: `youtube.com`, `youtu.be`, and `youtube-nocookie.com` over `http` or `https`.
- **Shorts Rejection**: Any path containing `youtube.com/shorts/` fails immediately with `"YouTube Shorts are blocked in FocusTube"`.
- **Identifier Extraction**: Matches `[?&]v=`, `youtu.be/`, `youtube.com/live/`, and `youtube.com/embed/` and requires at least 6 identifier characters.

Valid identifiers normalize to `https://www.youtube.com/watch?v=<id>`.

## 3.2 Asynchronous Metadata Retrieval

`core/library.lua` invokes `yt-dlp` via `vim.system` asynchronously so Neovim remains responsive during network requests:

```
yt-dlp --dump-json --no-playlist --no-warnings --skip-download --js-runtimes deno <canonical_url>
```

When `deno` is present on `PATH`, `--js-runtimes deno` is appended so `yt-dlp` evaluates YouTube's JavaScript signature challenges using Deno rather than requiring Node.js or Python plugins.

## 3.3 Record Normalization

Upon exit code `0`, `library.add_url` decodes the first JSON line from stdout via `utils/json.lua` and persists `id`, `url`, `title`, `channel` (from `uploader` or `channel`), `duration_sec`, `category`, and `watch_later` into SQLite.

---
[Previous: Page 02](./02-architecture-and-modules.md) | [Index](./README.md) | [Next: Page 04](./04-sqlite-persistence-and-schema.md)
