# Architecture

Friday is three loosely coupled pieces. Any of them can fail without taking the others (or your desktop) down.

## 1. The shell (`shell/`, Quickshell config `friday`)

A separate Quickshell instance, *not* part of illogical-impulse, so ii updates can't break it.

- **`Brain.qml`** (singleton): conversation state, the `friday-ask` process, stream-json parsing, approvals, sign-in state, live context, focus sessions, plan usage, and the `friday` IPC target.
- **`FridayPanel.qml`**: an always-mapped, click-through layer (`quickshell:friday`). Keeping the surface mapped avoids a map/unmap hitch on every open; input and keyboard focus are only taken while it's shown.
- **`Theme.qml`**: tokens only. Dark/light follows ii's generated scheme by luminance.

IPC (`qs -c friday ipc call friday <fn>`): `toggle`, `show`, `hide`, `ask <text>`, `withSelection <text>`, `newChat`, `resume`, `approval <json>`, `cloak <ms>`, `ping`.

## 2. The brain (`brain/`, installed at `~/.local/share/friday`)

| Helper | Role |
|---|---|
| `friday-ask` | Finds `claude`, adds desktop context (time, focused window, clipboard when you say "this"), runs `claude -p --output-format stream-json` with the policy hook. |
| `friday-approve` | Claude Code `PreToolUse` hook: allow / ask (approval card over IPC) / deny. Appends every decision to `audit.log`. |
| `friday-context` | One JSON line of "right now" for the UI and for Claude. |
| `friday-screen`, `friday-windows`, `friday-open`, `friday-web`, `friday-do` | Eyes and hands. |
| `friday-remind`, `friday-focus` | systemd user timers (reminders survive Friday closing). |
| `friday-usage` | Claude plan limits → `$XDG_RUNTIME_DIR/friday/usage.json` (read by the panel and the ii bar). |
| `friday-login` | Sign-in check and one-click sign-in terminal. |
| `friday-profile` | Generates `device-profile.md` (hardware, packages, repos, tools) once a day. |
| `friday-integrate` | The ii hooks (below). |
| `friday-toggle` | Keybind entry point; starts the shell if needed. |

`CLAUDE.md` is Friday's operating manual. It imports `me.md` (private), `device-profile.md` and `memory/notes.md`.

## Voice (`brain/voice/friday_voice.py`, via `friday-voice`)

A child process of the shell, speaking JSON lines over stdio, so the UI and the audio never block each other.

```
pw-record 16 kHz ─▶ IDLE: Vosk (Indian English) grammar ["hey friday", "okay friday", "hi friday", "friday"]
   ─(hit)─▶ Whisper small.en re-reads the last 2 s, silently ─(really you)─▶ chime + panel, LISTEN
            (nothing is shown until it's confirmed; audio keeps buffering, so "Friday, open Chrome" in one breath works)
LISTEN: Vosk partials, then Whisper re-reading every ~1.2 s → "partial" events (live words)
        raw-mic RMS vs a percentile noise floor → ends after 1.1 s of quiet
     ─▶ Whisper small.en (beam 5, vocabulary prompt) → "final" → Brain.ask(text) with FRIDAY_VOICE=1
answer streams in ─▶ each block's first paragraph ─▶ "say+" ─▶ Piper, one sentence per utterance (longer
     comma breaths via repeated pause tokens, a pause after each full stop) ─▶ pacat; a "word" event as each
     word is heard, snapped to the real pauses (word-by-word highlight)
reply ends with a hidden [[listen]] / [[end]] tag (Claude's call): listen for a follow-up, or say goodbye and close
```

The tag is stripped from the screen, from speech and from History; no tag means "listen".

The mic is ignored while Friday speaks (and doesn't move the automatic gain), so it never wakes itself.

Events: `hello`, `ready`, `unavailable`, `muted`, `prewake`, `wake`, `level`, `partial`, `transcribing`, `final`, `cancel`, `speaking`, `words`, `word`, `error`.
Commands: `listen [followup]`, `cancel`, `stop`, `mute`, `unmute`, `say <json>`, `say+ <json>`, `say-end`, `quit`.
Models live in `brain/.voice/`, the Python env in `brain/.venv/` (both git-ignored, created by `friday-voice-setup`).
Debug log: `brain/.voice/voice.log` (set `FRIDAY_VOICE_DEBUG=1` for every wake-word guess).

## On-device skills (`friday-local`) and autostart (`friday-start`)

```
you ask (typed or spoken) ─▶ friday-local (~0.1 s, no network for most)
   handled ─▶ answer shown/spoken right away, the action done with wpctl / brightnessctl / playerctl / friday-open /
              friday-web / friday-remind / friday-focus / hyprctl / nmcli / grim …  (no Claude usage)
   declined ─▶ online? ─▶ Claude (anything friday-local handled just before goes along as context)
            └─ offline ─▶ "I'm offline, here's what I can still do"
```

It is deliberately conservative: anchored patterns, and "not sure" means Claude. A wrong guess costs more than a
little usage. Phrasings come from built-in variations plus `~/.local/state/friday/phrases.json`, which
`friday-phrases` refreshes at most once a week with one Haiku call (`FRIDAY_PHRASES=off` to disable).

`friday-start` is run once by Hyprland at login. It starts `qs -c friday`, checks every 5 s and restarts it if it
died (it gives up with a notification after 5 crashes in a row), and kicks off the weekly phrase refresh.
`friday-start --restart` after updates, `--stop` to stop until next login.

Nothing calls Claude in the background except that weekly phrase refresh. Session titles are made locally, and
`friday-usage` only reads the usage meter.

## 3. The ii hooks (`friday-integrate`)

Small, marked insertions into illogical-impulse:

| File | Hook |
|---|---|
| `services/LauncherSearch.qml` | "Ask Friday" row in the Super search (first for questions and long queries). |
| `services/Ai.qml` (+ `services/ai/ClaudeCliApiStrategy.qml`) | A *Friday* model in the AI sidebar. |
| `modules/ii/bar/Resources.qml`, `ResourcesPopup.qml` | CPU → RAM → Claude 5-hour → Claude weekly (swap removed), with details on hover. |

Rules: every anchor must match exactly once or that file is skipped whole; a backup is taken before patching; `--revert` restores stock exactly; `--status` reports; `--no-bar` / `--no-sidebar` opt out; `touch ~/.local/state/friday/no-integrate` disables it at login.
