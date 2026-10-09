# Project Friday

**A Claude-powered assistant that lives inside your Linux desktop.**
Press <kbd>Super</kbd> + <kbd>Space</kbd> (or say "Hey Friday"), say what you want, and Friday sees your screen, knows your machine, and does the work. It asks before anything risky.

```bash
curl -fsSL https://raw.githubusercontent.com/once-human/project-friday/main/install.sh | bash
```

One command on any Linux desktop: it detects your distro and desktop, installs what's missing, and hooks Friday in. Built on **[Claude Code](https://claude.com/claude-code)** and **[Quickshell](https://quickshell.org)**, and at its best on **Arch + Hyprland + [illogical-impulse](https://github.com/end-4/dots-hyprland)**.

---

## What it does

| | |
|---|---|
| **Summon anywhere** | <kbd>Super</kbd>+<kbd>Space</kbd> opens a Spotlight-style glass panel on the focused monitor. Type, or pick a suggestion with <kbd>↑</kbd><kbd>↓</kbd> <kbd>↵</kbd>. |
| **Knows what you're doing** | The focused app, workspace, media, battery, Wi-Fi and clipboard shape its suggestions ("Explain the error on my screen" in a terminal, "Summarize this page" in a browser). |
| **Sees your screen** | Takes a screenshot when you ask "what's this?" and reasons about what's actually there. |
| **Acts, not just answers** | Opens apps, tabs and searches in your browser, arranges windows, controls media and volume, sets reminders, runs focus sessions, reads logs, inspects repos. |
| **Talk to it** | <kbd>Super</kbd>+<kbd>Ctrl</kbd>+<kbd>Space</kbd> (or "Hey Friday" when you switch the wake word on). Your words appear live, Whisper turns them into an accurate request, and Friday reads its whole answer back in a natural neural voice, each word lighting up as it's spoken (code and tables stay on screen). Say "Friday" or "Hey Friday". By voice it's conversational (short and casual for small talk, calm and focused for real work); typed, it's regular Claude. After each answer Friday decides, like a person would, whether you'll reply: if it asked you something it keeps listening; if you said "goodnight" or you're clearly done, it says its goodbye and closes. Approval cards take a spoken "yes" / "no". Listening is 100% local; the natural voice sends only the text being spoken to Microsoft's speech service (set `FRIDAY_TTS=piper` for a fully local voice; it falls back to that automatically offline). |
| **Writing tools** | Highlight text anywhere and press <kbd>Super</kbd>+<kbd>Shift</kbd>+<kbd>Space</kbd> to explain, summarize, proofread, rewrite, make it professional, or translate. |
| **Everyday stuff without Claude** | Time, date, world clock, timers and reminders (it says them out loud when they go off), volume, brightness, play/pause/next, "play some Fred again", open apps and sites, Google something, weather, battery, Wi-Fi/Bluetooth, CPU/RAM/disk, screenshots, lock, workspaces, maths, unit conversion, coin/dice, your Claude usage, small talk and jokes. All handled on your laptop in ~0.1 s: **no Claude usage, and it works offline**. Only what it can't do goes to Claude; offline, it tells you so instead of hanging. Answers are phrased from a bank of variations that Claude refreshes once a week (one tiny call), so it doesn't sound canned. |
| **Made for one person** | A greeting and one status line about your world, plus rows for what you actually do: jump back into your latest Claude Code sessions (auto-titled like *Continue Friday Overlay Polish*, with project and time) right where you left them, see what's on your connected phone (adb/fastboot), or start a 90-minute deep-work block. |
| **One-tap music** | A row split five ways: House · Afro · Fred · Techno · Chill. Pick one (← → or click) and a long mix starts playing in the background (`mpv` + `yt-dlp`, installed for you), or the first YouTube result opens already playing. "Play some Fred again" works too. |
| **Uses your mouse and keyboard** | For apps with no command line, Friday looks at the screen, clicks and types (`friday-input`: `wtype` + `ydotool` on Wayland, `xdotool` on X11; the installer sets them up). Moving and scrolling are free; every click or keystroke shows an approval card unless you set `FRIDAY_INPUT_TRUST=1`. |
| **Deep work** | A live countdown card with a progress ring, plus a notification when you're done. |
| **Safe by design** | Every action passes a policy hook: read-only runs silently, changes need your approval, and `sudo` or disk-wiping commands are refused. All of it is logged. |
| **Claude limits in your bar** | Your 5-hour and weekly plan usage appear as rings next to CPU and RAM. The ring is usage; the dot is how far through the window you are. |
| **Native to ii** | On illogical-impulse it also adds an "Ask Friday" row to the Super search, a *Friday* model to the AI sidebar, and Claude usage rings in the bar. Update-safe and reversible. |

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/once-human/project-friday/main/install.sh | bash
```

or from a clone: `git clone https://github.com/once-human/project-friday && cd project-friday && ./install.sh`

The installer asks once before using `sudo`, then does everything itself:

1. detects your distro, package manager and desktop
2. installs what's missing: **Quickshell** (from the AUR, a COPR, or built from source), **Claude Code** (Anthropic's official installer), clipboard, screenshot, media and audio tools, and the icon font
3. links Friday in (`~/.config/quickshell/friday → shell/`, `~/.local/share/friday → brain/`), so `git pull && ./install.sh` updates it
4. adds a keyboard shortcut, autostart (Friday restarts itself if it ever crashes) and app-menu entries for your desktop
5. offers voice (~700 MB of local speech models), then starts Friday

Flags: `--yes` (no questions), `--no-voice`, `--no-deps` (don't touch system packages), `--dry-run` (show what it would do).
Then tell Friday about yourself in `brain/me.md` (git-ignored, like your memory and settings). Remove everything with `./uninstall.sh`.
You need a Claude **Pro, Max, Team, Enterprise or Console** account for Claude Code; the first time, Friday shows a **Sign in** card.

### Where it runs

| | Status | Notes |
|---|---|---|
| **Arch + Hyprland + illogical-impulse** | ⭐ Recommended | Everything, including the ii hooks (Super search row, sidebar model, usage rings in the bar) and frosted-glass blur |
| Hyprland (any distro, no ii) | ✅ Full | Everything except the ii hooks |
| Sway, niri, river, labwc, Wayfire, COSMIC | ✅ Supported | Window context, screenshots and clicking work through each compositor's own tools; shortcut is <kbd>Super</kbd>+<kbd>Alt</kbd>+<kbd>Space</kbd> on Sway (niri/river: one line to add, the installer prints it) |
| KDE Plasma (Wayland or X11) | ✅ Supported | Add the shortcut once in System Settings (the installer tells you how); window titles need `kdotool` |
| X11 desktops (XFCE, Cinnamon, MATE, i3, …) | ✅ Supported | Through Quickshell's X11 backend; XFCE gets its shortcut automatically |
| GNOME | 🧪 Experimental | GNOME's Wayland session has no overlay protocol, so Friday runs through XWayland; shortcut is set automatically. GNOME doesn't expose window info, so "what's this window" relies on screenshots |
| Distros | Arch & derivatives, Fedora, openSUSE: packaged Quickshell. Debian 13+/Ubuntu 25.04+, Void, RHEL-likes: Quickshell built from source (needs Qt 6.6+; Ubuntu 24.04 is too old). NixOS/Gentoo: the installer prints what to add. |
| macOS · Windows | ❌ Not yet | Friday lives inside the Linux desktop (Quickshell). Native apps are on the roadmap |

Details, manual install and per-distro notes: [docs/install.md](docs/install.md).

### Voice

The installer offers it; to add it later:

```bash
~/.local/share/friday/bin/friday-voice-setup     # ~700 MB of local models, one time
~/.local/share/friday/bin/friday-start --restart
~/.local/share/friday/bin/friday-voice --test    # say something; it should repeat it back
```

| Piece | What | Why |
|---|---|---|
| Wake word | [Vosk](https://alphacephei.com/vosk/) small **Indian-English** model, grammar locked to "hey friday", then Whisper confirms it was really you before anything shows | off by default (toggle **Hey Friday** in Friday's footer); when on it costs a few % of one core, and the double check kills most false wakes |
| Live words | Vosk streaming partials, corrected by Whisper every ~1 s | what you see while talking is what gets sent |
| Final transcript | [faster-whisper](https://github.com/SYSTRAN/faster-whisper) `small.en` (int8 on CPU, float16 on CUDA), biased with your own vocabulary | accurate on accents and jargon (Hyprland, PixelOS, fastboot…) |
| Voice | Microsoft neural voice `en-US-AvaNeural` via [edge-tts](https://github.com/rany2/edge-tts) when online, [Piper](https://github.com/OHF-Voice/piper1-gpl) `en_GB-jenny_dioco-medium` offline | sounds like a person, with the voice's own word timings driving the highlight; Piper keeps it working with no internet (`FRIDAY_TTS=piper` to always stay local; `FRIDAY_NEURAL_VOICE` to pick another voice, e.g. `en-GB-SoniaNeural`, `en-IN-NeerjaNeural`) |

Tune it in `brain/config.env` (model size, voice, silence before it stops listening, wake word on/off).

## Keys

| Key | Action |
|---|---|
| <kbd>Super</kbd>+<kbd>Space</kbd> | Open / close Friday (Sway, GNOME, XFCE: <kbd>Super</kbd>+<kbd>Alt</kbd>+<kbd>Space</kbd>, so your desktop's own keys stay untouched) |
| <kbd>Super</kbd>+<kbd>Shift</kbd>+<kbd>Space</kbd> | Friday on your highlighted text (others: add <kbd>Alt</kbd>) |
| "Hey Friday" · <kbd>Super</kbd>+<kbd>Ctrl</kbd>+<kbd>Space</kbd> · <kbd>Ctrl</kbd>+<kbd>M</kbd> | Talk to Friday (others: add <kbd>Alt</kbd>) |
| <kbd>↑</kbd> <kbd>↓</kbd> · <kbd>↵</kbd> | Pick a suggestion · run it / send |
| <kbd>Ctrl</kbd>+<kbd>N</kbd> | New chat (closing Friday also ends the chat) |
| <kbd>Ctrl</kbd>+<kbd>H</kbd> or **History** (right of the status line) | History: your last 10 chats; type to filter, <kbd>↵</kbd> to continue one, <kbd>Del</kbd> to remove, or *Clear history* |
| <kbd>↵</kbd> / <kbd>Esc</kbd> on an approval | Allow / don't allow (high-risk needs <kbd>Ctrl</kbd>+<kbd>↵</kbd>) |
| <kbd>Esc</kbd> | Clear input → clear selection → close |

Every time you close Friday the chat is filed into History, so it always opens fresh; your last chat is one row away as *Continue*.

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
hypr/friday.conf       Hyprland: keybinds, autostart, blur rules
desktop/               other desktops: Sway include, autostart entry, systemd unit, app-menu entries, icon
docs/                  install, architecture, safety model, troubleshooting
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

Native macOS and Windows apps · Gmail / Calendar via MCP · scheduled routines · per-app skills · more on-device skills.

## Credits

[Claude Code](https://claude.com/claude-code) · [Quickshell](https://quickshell.org) · [edge-tts](https://github.com/rany2/edge-tts) · [Piper](https://github.com/OHF-Voice/piper1-gpl) · [Vosk](https://alphacephei.com/vosk/) · [faster-whisper](https://github.com/SYSTRAN/faster-whisper) · [Material Symbols](https://github.com/google/material-design-icons) (Apache 2.0) · [illogical-impulse](https://github.com/end-4/dots-hyprland) by end-4 · [Source Serif 4](https://github.com/adobe-fonts/source-serif) (SIL OFL 1.1).
Friday is a personal project and is not affiliated with Anthropic.
