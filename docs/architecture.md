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

## 3. The ii hooks (`friday-integrate`)

Small, marked insertions into illogical-impulse:

| File | Hook |
|---|---|
| `services/LauncherSearch.qml` | "Ask Friday" row in the Super search (first for questions and long queries). |
| `services/Ai.qml` (+ `services/ai/ClaudeCliApiStrategy.qml`) | A *Friday* model in the AI sidebar. |
| `modules/ii/bar/Resources.qml`, `ResourcesPopup.qml` | CPU → RAM → Claude 5-hour → Claude weekly (swap removed), with details on hover. |

Rules: every anchor must match exactly once or that file is skipped whole; a backup is taken before patching; `--revert` restores stock exactly; `--status` reports; `--no-bar` / `--no-sidebar` opt out; `touch ~/.local/state/friday/no-integrate` disables it at login.
