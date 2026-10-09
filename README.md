# Project Friday

**A Claude-powered assistant that lives inside your Linux desktop.**
Press <kbd>Super</kbd> + <kbd>Space</kbd> (or say "Hey Friday"), say what you want, and Friday sees your screen, knows your machine, and does the work. It asks before anything risky.

```bash
curl -fsSL https://raw.githubusercontent.com/once-human/project-friday/main/install.sh | bash
```

One command on any Linux desktop: it detects your distro and desktop, installs what's missing, and hooks Friday in. Built on **[Claude Code](https://claude.com/claude-code)** and **[Quickshell](https://quickshell.org)**, and at its best on **Arch + Hyprland + [illogical-impulse](https://github.com/end-4/dots-hyprland)**.

> [!IMPORTANT]
> **This is a personal project.** I built Friday for my own laptop and I'm sharing it because it's fun and it might be useful to you. You're very welcome to use it, fork it, rip parts out of it, whatever you like. Just know what you're getting:
>
> - It's provided **as is**, with no warranty and no support promise ([MIT license](LICENSE)). I fix things when I can.
> - **It lets an AI run commands on your computer.** Risky actions show an approval card and the worst ones are blocked ([how](docs/safety.md)), but it's not a sandbox and no guard is perfect. Read the cards before you hit Allow. **You use it at your own risk.**
> - Your requests go to Anthropic through Claude Code (your own account, your own usage), and spoken answers go to Microsoft's speech service unless you switch to the local voice. Details in [SECURITY.md](SECURITY.md).
> - It's not affiliated with or endorsed by Anthropic, Microsoft, Google or anyone else whose stuff it uses. "Claude" is a trademark of Anthropic.

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
| **Music that gets you** | "Play something nice" plays something *you'd* pick: it knows your taste (`FRIDAY_MUSIC`, plus what you play, like and skip) and the vibe you asked for. "High energy Fred again" finds his Boiler Room set; "afro house for the gym" a peak-time mix; a song plays and then keeps going with similar tracks. Every YouTube result is vetted first (music only, never a news clip), and "I love this", "not this", "more like this" teach it. The music row is *For you* plus your favourites. Plays in the background with `mpv` + `yt-dlp` (installed for you), or in your browser. |
| **Offline brain** | No internet, or out of Claude usage? Friday keeps going on a free open model running on your own laptop (Qwen3 via Ollama, size of your choice): no keys, no limits, nothing leaves the machine. Same panel, same voice, same safety guard; Claude picks the chat back up when it's available. |
| **Your call, all of it** | `project-friday mode private` and everything (thinking, listening, speaking) stays on your laptop; `mode local` drops Claude entirely; `mode default` puts it back. Every other knob is one `project-friday set` away, with a default to return to. |
| **Uses your mouse and keyboard** | For apps with no command line, Friday looks at the screen, clicks and types (`friday-input`: `wtype` + `ydotool` on Wayland, `xdotool` on X11; the installer sets them up). Moving and scrolling are free; every click or keystroke shows an approval card unless you set `FRIDAY_INPUT_TRUST=1`. |
| **Deep work** | A live countdown card with a progress ring, plus a notification when you're done. |
| **Safe by design** | Every action passes a policy hook: read-only runs silently, changes need your approval (the card shows the whole command, and you have to scroll through it before Allow works), and `sudo`, disk-wiping commands, credentials, browser data and Friday's own files are off-limits. All of it is logged. See [SECURITY.md](SECURITY.md). |
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
3. links Friday in (`~/.config/quickshell/friday → shell/`, `~/.local/share/friday → brain/`), so `project-friday update` keeps it current
4. adds a keyboard shortcut, autostart (Friday restarts itself if it ever crashes) and app-menu entries for your desktop
5. offers voice (~700 MB of local speech models) and the offline brain (you pick the size, 1.4 to 9 GB), then starts Friday

Flags: `--yes` (no questions; never downloads the offline brain unasked), `--offline=balanced` (pick its size up front), `--no-voice`, `--no-offline`, `--no-deps` (don't touch system packages), `--dry-run` (show what it would do).

After that, everything is one command, `project-friday` (or just `friday` if nothing else on your system uses that name). `project-friday help` lists it all:

| | |
|---|---|
| `project-friday status` | running? signed in? which mode, voice, offline brain, Claude usage |
| `project-friday restart` · `start` · `stop` | restart it if it's ever stuck · start · stop until next login |
| `project-friday mode local` | switch modes: `default`, `local` or `private` ([below](#modes-and-settings)) |
| `project-friday settings` · `set NAME VALUE` · `reset NAME\|all` | every setting with its value and default · change one · back to defaults |
| `project-friday offline setup` · `models` · `use` · `remove` · `test` | the offline brain: install, see sizes, switch model, delete one, try it |
| `project-friday update` | pull the latest version, re-link, restart |
| `project-friday ask "…"` | open Friday and ask something from a terminal or script |
| `project-friday music "…"` | play something (`stop`, `next`, `like`, `more`, `taste`) |
| `project-friday voice setup` · `voice test` | install / check voice |
| `project-friday config` · `me` | edit `config.env` by hand · what Friday knows about you |
| `project-friday logs` | recent voice and shell logs, and the guard's last decisions |
| `project-friday uninstall` | remove everything Friday added (your `brain/` files stay) |

### Make it yours

Friday works out of the box, but it's much better once it knows you. Two git-ignored files in `brain/` (so your personal stuff never ends up in a commit):

- **`me.md`**: who you are, what you work on, how you like answers. Friday reads it on every request. Start from [`me.example.md`](brain/me.example.md).
- **`config.env`**: settings. Change them with `project-friday set NAME VALUE` (or edit the file; start from [`config.example.env`](brain/config.example.env)). The personal ones:

| Setting | What it does |
|---|---|
| Command | What it does |
|---|---|
| `project-friday set name Sam` | What Friday calls you (defaults to the first name on your account) |
| `project-friday set style "casual, short, a bit of slang"` | How you talk, so on-device replies match your vibe |
| `project-friday set vocab "Hyprland, fastboot, MyApp"` | Names and jargon the speech recogniser should expect |
| `project-friday set rom-dirs "~/aosp ~/lineage"` | Android ROM build trees, so Friday can tell you when a build is running |
| `project-friday set music "Fred again.., afro house, lofi"` | Artists and genres you like, favourites first (your music row and "play something nice") |

Friday also keeps its own notes about how you work in `brain/memory/notes.md`; you can read and edit them any time.

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
project-friday voice setup     # ~700 MB of local models, one time
project-friday restart
project-friday voice test      # say something; it should repeat it back
```

| Piece | What | Why |
|---|---|---|
| Wake word | [Vosk](https://alphacephei.com/vosk/) small **Indian-English** model, grammar locked to "hey friday", then Whisper confirms it was really you before anything shows | off by default (toggle **Hey Friday** in Friday's footer); when on it costs a few % of one core, and the double check kills most false wakes |
| Live words | Vosk streaming partials, corrected by Whisper every ~1 s | what you see while talking is what gets sent |
| Final transcript | [faster-whisper](https://github.com/SYSTRAN/faster-whisper) `small.en` (int8 on CPU, float16 on CUDA), biased with your own vocabulary | accurate on accents and jargon (Hyprland, fastboot, your own project names via `FRIDAY_VOCAB`…) |
| Voice | Microsoft neural voice `en-US-AvaNeural` via [edge-tts](https://github.com/rany2/edge-tts) when online, [Piper](https://github.com/OHF-Voice/piper1-gpl) `en_GB-jenny_dioco-medium` offline | sounds like a person, with the voice's own word timings driving the highlight; Piper keeps it working with no internet (`FRIDAY_TTS=piper` to always stay local; `FRIDAY_NEURAL_VOICE` to pick another voice, e.g. `en-GB-SoniaNeural`, `en-IN-NeerjaNeural`) |

Tune it in `brain/config.env` (model size, voice, silence before it stops listening, wake word on/off).

## Offline brain

Friday's everyday skills never needed Claude or the internet. The **offline brain** covers the rest: a free, open model running **on your laptop** that takes over whenever you're offline, your Claude limit runs out, or Claude is down. No account, no API keys, no usage limits, free forever, and nothing leaves your machine. The installer offers it and lets you pick the size (it never downloads gigabytes without asking); add or change it any time:

```bash
project-friday offline models          # the sizes, and which one suits this laptop
project-friday offline setup           # pick one from a menu (installs Ollama the first time)
project-friday offline setup balanced  # or name it straight away
project-friday offline test            # ask it something
project-friday offline use smart       # switch model (downloads it if needed)
project-friday offline remove small    # free the space again
```

| Size | Model | Download | Runs well on | Good for |
|---|---|---|---|---|
| `small` | `qwen3:1.7b` | 1.4 GB | any laptop | quick answers, basic tasks |
| `balanced` | `qwen3:4b` | 2.5 GB | 8 GB RAM | a good everyday helper (recommended without a GPU) |
| `smart` | `qwen3:8b` | 5.2 GB | a 6 GB GPU (16 GB RAM works, but slow and heavy) | noticeably smarter |
| `smartest` | `qwen3:14b` | 9.3 GB | a 12 GB GPU (32 GB RAM works, but slow and heavy) | best quality |

Any other [Ollama model](https://ollama.com/library) that supports tools works too (`project-friday offline use gemma3:4b`), or point `project-friday set local-url http://127.0.0.1:8080/v1/chat/completions` at another server on your machine (llama.cpp, LM Studio). It answers in the same panel and voice, can still run commands, read files and use Friday's helpers (through the same guard, so the same things are allowed, asked about or refused), and says once per chat that it's standing in; when Claude's back, Claude picks up the chat. Be realistic about it: a small local model is good for questions, quick tasks and chat, slower on a CPU-only laptop, and no match for Claude on big jobs. It'll say so.

## Staying light

Friday is meant to cost nothing when you're not using it:

| Part | While you're not using it | While it works |
|---|---|---|
| **Panel** | unmapped: no window, no compositor or blur work, nothing drawn | a normal window |
| **Supervisor** (`friday-start`) | waits on the panel's process, no polling | — |
| **Offline brain** | not running: the model leaves memory 2 minutes after an answer and Friday stops Ollama's server shortly after | runs at low CPU/disk priority on half your cores, one model at a time |
| **Voice, wake word off** | no microphone, no models in memory (unloaded 5 minutes after you last talked) | loads when you press the talk key |
| **Voice, wake word on** | a small always-on listener plus the speech model in memory (~0.5 GB); while a video or music is playing it only checks clear "Hey Friday"s, and backs off after false alarms | |
| **Background** | Claude usage every 15 minutes (3 while the panel is open; `usage-check off` stops it), a phrase refresh once a week | |

`project-friday status` shows what Friday is using right now. Tune it: `set local-keep 30s` (less RAM) or `10m` (faster follow-ups), `set local-threads 2`, `set voice-unload 2`, `set stt-threads 2`; `project-friday offline stop` frees the offline brain immediately. On a laptop without a GPU, the `small` or `balanced` offline brain is the sweet spot: every reply runs on your CPU, and the bigger ones make it work much harder. If Ollama was installed with its own installer, it runs as a system service all the time; Friday doesn't need that (`sudo systemctl disable --now ollama`).

## Modes and settings

One switch for how Friday thinks and what leaves your laptop:

| `project-friday mode …` | Thinking | Voice | Background calls | Needs a Claude account |
|---|---|---|---|---|
| **`default`** | Claude; the offline brain when you're offline or out of usage | natural neural voice online, Piper offline | weekly phrase refresh, usage rings | yes |
| **`local`** | the offline brain, always (no Claude usage at all) | as you set it | as you set it | no |
| **`private`** | the offline brain, always | Piper, on-device | none | no |

In `private` mode nothing leaves your laptop on its own: listening, speech, thinking and everyday skills are all on-device. Things you explicitly ask for that live on the internet (playing music from YouTube, the weather, a web search) still go online, because that's the request.

Everything else is a named setting. `project-friday settings` shows each one with its current value, its default and what it does; `project-friday set NAME VALUE` changes it, `project-friday set NAME default` (or `reset NAME`) puts it back, and `project-friday reset all` returns everything to defaults (keeping your name, style and music; `reset everything` clears those too). A few:

| Setting | Values (default first) | |
|---|---|---|
| `brain` | `auto` · `claude` · `local` | who thinks (what the modes switch) |
| `tts` | `auto` · `neural` · `piper` | which voice speaks |
| `stt-model` | `small.en` · `tiny.en` · `base.en` · `medium.en` · `large-v3-turbo` | speech recognition accuracy vs speed |
| `claude-model` / `voice-claude-model` | your Claude Code default / `sonnet` | which Claude for typed / spoken requests |
| `local-model` | best one you've pulled | the offline brain's model |
| `speak` | `on` · `off` | read answers aloud |
| `local-skills` | `on` · `off` | answer everyday things on the laptop first |
| `phrases` · `usage-check` | `on` · `off` | the weekly phrase refresh · the usage rings |
| `input-trust` | `0` · `1` | let Friday click and type without asking |

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

- **Where your data goes**: requests Friday can't answer on-device go to Anthropic via Claude Code (when you're offline or out of Claude usage, the offline brain answers on your laptop instead); spoken answers go to Microsoft's speech service when the neural voice is on (`FRIDAY_TTS=piper` keeps speech local); weather lookups send the place name to wttr.in. Listening, the wake word and everyday answers stay on your laptop. Full list in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md#services-friday-talks-to).
- **Signing in** uses Claude Code's own login. Friday never touches browser cookies.
- **The neural voice** uses [edge-tts](https://github.com/rany2/edge-tts), an unofficial client for Microsoft Edge's read-aloud service. It could change or stop working; Friday then falls back to Piper on its own.
- **Plan usage** (`friday-usage`) reads the token Claude Code stored locally and calls the same endpoint as Claude Code's `/usage`. That endpoint is undocumented, so it may change. If it fails, the rings simply hide.
- **ii updates**: `friday-integrate` re-applies its marked hooks at login, or skips them cleanly (with one notification) if ii's code changed. Friday itself never depends on them.

## Roadmap

Native macOS and Windows apps · Gmail / Calendar via MCP · scheduled routines · per-app skills · more on-device skills.

## Contributing

Issues and pull requests are welcome, but this is a side project, so replies can be slow and I may say no to things that don't fit how I use it. Forking it and making it your own is totally fine (and encouraged). Security problems: please report privately, see [SECURITY.md](SECURITY.md).

## Credits

[Claude Code](https://claude.com/claude-code) · [Quickshell](https://quickshell.org) · [edge-tts](https://github.com/rany2/edge-tts) · [Piper](https://github.com/OHF-Voice/piper1-gpl) with the **Jenny (Dioco)** voice · [Vosk](https://alphacephei.com/vosk/) · [faster-whisper](https://github.com/SYSTRAN/faster-whisper) · [Material Symbols](https://github.com/google/material-design-icons) · [illogical-impulse](https://github.com/end-4/dots-hyprland) by end-4 · [Source Serif 4](https://github.com/adobe-fonts/source-serif). Licenses for all of these: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

[MIT](LICENSE) © Onkar Yaglewad. Provided as is, without warranty; you use it at your own risk.

Project Friday is an independent personal project. It is not affiliated with, sponsored by or endorsed by Anthropic, Microsoft, Google or any other company mentioned here. "Claude" and "Claude Code" are trademarks of Anthropic, PBC; other names are trademarks of their owners.
