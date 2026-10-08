# Safety model

Friday can run commands on your machine, so every tool call Claude makes is checked by `brain/bin/friday-approve` (a Claude Code `PreToolUse` hook) *before* it runs.

| Tier | Examples | What happens |
|---|---|---|
| **allow** | reading files, `hyprctl clients`, `git status`, media/volume/brightness, screenshots, Friday's own helpers, opening URLs | runs silently |
| **ask** | installing/removing packages, editing files outside Friday's folder, `git commit`/`push`, `kill`, launching programs, service restarts, `adb`/`fastboot` | an approval card appears; Enter allows, Esc denies (high risk needs Ctrl+Enter); no answer in 120 s = deny |
| **deny** | `sudo`/root, disk-destroying commands, credentials, browser cookies/profiles, SSH/GPG keys | refused, with an explanation |

- Every decision goes to `brain/audit.log` (git-ignored).
- If the panel isn't running, "ask" becomes "deny", with a notification.
- Text from web pages, files, clipboard or highlighted selections is treated as data, never as instructions (`CLAUDE.md`).
- Friday never commits or pushes unless you explicitly ask.
