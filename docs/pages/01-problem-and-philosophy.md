# Page 01: Problem Statement and Design Philosophy

## 1.1 Attention Fragmentation in Web Video Interfaces

Modern web video platforms couple content delivery with engagement-maximizing interfaces: algorithmic recommendation sidebars, autoplay countdowns, comment threads, and short-form vertical feeds. For technical learners—and particularly for users managing Attention-Deficit/Hyperactivity Disorder (ADHD)—these competing stimuli create a high probability of involuntary task switching.

## 1.2 Separation of Curation from Playback

FocusTube.nvim resolves this by splitting the workflow into two distinct phases:

1. **Intentional Curation**: Before a study session begins, the user explicitly registers educational YouTube URLs into a local library.
2. **Isolated Playback**: During the session, Neovim acts as the control plane and study workspace while `mpv` renders only the video stream in a standalone window.

## 1.3 Core Engineering Principles

- **Zero Browser Surface**: No web views, embedded iframes, or recommendation APIs are queried.
- **Local-First Persistence**: Library metadata, playback timestamps, bookmarks, notes, and focus sessions are stored in SQLite.
- **Explicit Library Approval**: `core/player.lua` refuses to launch any video identifier absent from the local `videos` table.
- **Crash-Resilient Progress**: Playback coordinates flush on a periodic timer, on pause events, and on editor exit.
- **Minimalist Presentation**: Floating windows display only controls relevant to the current study context.

---
[Index](./README.md) | [Next: Page 02](./02-architecture-and-modules.md)
