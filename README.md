# Project Friday

**A Claude-powered assistant that lives inside your Linux desktop.**
Press <kbd>Super</kbd> + <kbd>Space</kbd>, say what you want, and Friday sees your screen, knows your machine, and does the work. It asks before anything risky.

Built for **Arch + Hyprland + [illogical-impulse](https://github.com/end-4/dots-hyprland)**, on top of **[Claude Code](https://claude.com/claude-code)** and **[Quickshell](https://quickshell.outfoxxed.me)**.

---

## What it does

| | |
|---|---|
| **Summon anywhere** | <kbd>Super</kbd>+<kbd>Space</kbd> opens a Spotlight-style glass panel on the focused monitor. Type, or pick a suggestion with <kbd>↑</kbd><kbd>↓</kbd> <kbd>↵</kbd>. |
| **Knows what you're doing** | The focused app, workspace, media, battery, Wi-Fi and clipboard shape its suggestions ("Explain the error on my screen" in a terminal, "Summarize this page" in a browser). |
| **Sees your screen** | Takes a screenshot when you ask "what's this?" and reasons about what's actually there. |
| **Acts, not just answers** | Opens apps, tabs and searches in your browser, arranges windows, controls media and volume, sets reminders, runs focus sessions, reads logs, inspects repos. |
| **Writing tools** | Highlight text anywhere and press <kbd>Super</kbd>+<kbd>Shift</kbd>+<kbd>Space</kbd> to explain, summarize, proofread, rewrite, make it professional, or translate. |
| **Made for one person** | A greeting and one status line about your world, plus rows for what you actually do: pick up your most recently touched repos (with uncommitted changes), check on a running PixelOS build, see what's on your connected phone (adb/fastboot), or start a 90-minute deep-work block. |
| **One-tap music** | A row split five ways: House · Afro · Fred · Techno · Chill. Pick one (← → or click) and a long mix starts in your browser, controllable from the bar. |
| **Deep work** | A live countdown card with a progress ring, plus a notification when you're done. |
| **Safe by design** | Every action passes a policy hook: read-only runs silently, changes need your approval, and `sudo` or disk-wiping commands are refused. All of it is logged. |
| **Claude limits in your bar** | Your 5-hour and weekly plan usage appear as rings next to CPU and RAM. The ring is usage; the dot is how far through the window you are. |
| **Native to ii** | Adds an "Ask Friday" row to the Super search and a *Friday* model to the AI sidebar. Update-safe and reversible. |

## Install

Requirements: Hyprland, illogical-impulse (Quickshell `qs`), [Claude Code](https://docs.claude.com/en/docs/claude-code) signed in once (`claude`), Python 3, `wl-clipboard`, `grim`, `libnotify`.
Optional: `playerctl`, `wireplumber` (`wpctl`), `brightnessctl`, `networkmanager`.

```bash
git clone https://github.com/once-human/project-friday ~/Projects/project-friday
cd ~/Projects/project-friday
./install.sh
hyprctl reload && qs -c friday -d
```

Then press <kbd>Super</kbd>+<kbd>Space</kbd>. If Claude Code isn't signed in, Friday shows a one-click **Sign in** card.

The installer **links** the repo into place, so `git pull` updates Friday instantly:

```
~/.config/quickshell/friday  →  shell/    the UI
~/.local/share/friday        →  brain/    Claude bridge, helpers, your private files
```

Edit **`brain/me.md`** to tell Friday who you are. It's git-ignored, as are your memory, device profile and audit log.

To remove everything cleanly: `./uninstall.sh`.

## Keys

| Key | Action |
|---|---|
| <kbd>Super</kbd>+<kbd>Space</kbd> | Open / close Friday |
| <kbd>Super</kbd>+<kbd>Shift</kbd>+<kbd>Space</kbd> | Friday on your highlighted text |
| <kbd>↑</kbd> <kbd>↓</kbd> · <kbd>↵</kbd> | Pick a suggestion · run it / send |
| <kbd>Ctrl</kbd>+<kbd>N</kbd> | New chat (the old one stays one row away as *Continue*) |
| <kbd>↵</kbd> / <kbd>Esc</kbd> on an approval | Allow / don't allow (high-risk needs <kbd>Ctrl</kbd>+<kbd>↵</kbd>) |
| <kbd>Esc</kbd> | Clear input → clear selection → close |

Coming back after more than 3 minutes starts a fresh chat automatically.

## Layout

```
shell/                 Quickshell config "friday" (UI)
  shell.qml
  services/Brain.qml   state, Claude stream parsing, approvals, context, focus, usage
  services/Theme.qml   design tokens: warm glass, one terracotta accent, motion curves
  ui/FridayPanel.qml   the panel: input, suggestions, conversation, sheets, footer
  ui/MessageDelegate.qml
  ui/Mark.qml          presence indicator
  assets/fonts/        Source Serif 4 (OFL) for replies
brain/                 runtime home (~/.local/share/friday)
  CLAUDE.md            Friday's persona, rules and tool catalogue (imports me.md)
  bin/friday-*         helpers (see docs/architecture.md)
  integration/         files friday-integrate places into ii
hypr/friday.conf       keybinds, autostart, blur rules
docs/                  architecture, safety model, troubleshooting
```

## How it fits together

```
Super+Space ──▶ Friday panel (Quickshell) ──▶ friday-ask ──▶ claude -p (stream-json)
                    ▲        │                       │
   live context ────┘        │            every tool call ──▶ friday-approve (policy hook)
   (friday-context)          │                                      │ needs you?
                             └──── approval card ◀── IPC ◀──────────┘
```

More in [docs/architecture.md](docs/architecture.md) and [docs/safety.md](docs/safety.md).

## Notes and caveats

- **Signing in** uses Claude Code's own login. Friday never touches browser cookies.
- **Plan usage** (`friday-usage`) reads the token Claude Code stored locally and calls the same endpoint as Claude Code's `/usage`. That endpoint is undocumented, so it may change. If it fails, the rings simply hide.
- **ii updates**: `friday-integrate` re-applies its marked hooks at login, or skips them cleanly (with one notification) if ii's code changed. Friday itself never depends on them.

## Roadmap

Voice ("Hey Friday" with local Whisper) · Gmail / Calendar via MCP · typing into apps · scheduled routines · per-app skills.

## Credits

[Claude Code](https://claude.com/claude-code) · [Quickshell](https://quickshell.outfoxxed.me) · [illogical-impulse](https://github.com/end-4/dots-hyprland) by end-4 · [Source Serif 4](https://github.com/adobe-fonts/source-serif) (SIL OFL 1.1).
Friday is a personal project and is not affiliated with Anthropic.
