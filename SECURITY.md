# Security

Project Friday is a personal project, maintained in my spare time, with no bug bounty and no guaranteed response time. That said, I care about it being safe to run, and reports are genuinely welcome.

## Reporting a problem

Please **don't open a public issue** for anything exploitable. Use GitHub's private reporting instead: the repository's **Security** tab → **Report a vulnerability**. Include what you did, what happened, and the Friday version you were on (`project-friday version`). I'll reply when I can and credit you in the fix if you'd like.

For anything that isn't exploitable (a command the guard asks about that it shouldn't, a confusing approval card), a normal issue is fine.

## What you're trusting when you run Friday

Read this before installing. Friday gives an AI model the ability to run commands as **your user** on **your computer**.

- **The model can be wrong or be manipulated.** Text it reads (web pages, files, emails, clipboard, window titles, command output) can contain instructions written by someone else ("prompt injection"). Friday tells Claude to treat all of that as data, and the guard below limits what it can do, but neither is perfect. **The approval card is the real safety net: read it before you press Allow.**
- **Your requests go to Anthropic.** Everything Friday can't answer on-device is sent through Claude Code to Anthropic, along with the desktop context it attaches (focused window title, a short clipboard/selection preview when relevant), screenshots you ask about, and the output of commands it runs. Read-only commands run without asking, so the contents of ordinary (non-sensitive) files Claude chooses to read can end up in that conversation.
- **The backup brain, if you set one up**, gets the same things Claude would when your Claude limit is reached (Gemini, Groq or OpenRouter, under their terms; Ollama stays local). Its keys live in `brain/config.env`, are never passed to Claude's environment or to the commands it runs, and Claude can't edit that file (reading it asks you). Its actions go through the same guard.
- **Spoken answers go to Microsoft** when the neural voice is on (the default when online). Set `FRIDAY_TTS=piper` in `brain/config.env` to keep speech fully local. Listening (wake word and transcription) is always local.
- **It's not a sandbox.** The guard is a policy check on each tool call, not an isolation boundary. Anything you approve runs with your full user permissions.

## How the guard works

Every tool call Claude makes passes through [`brain/bin/friday-approve`](brain/bin/friday-approve), a Claude Code `PreToolUse` hook (matcher `*`, so it sees every tool), **before** it runs. The full policy is in [docs/safety.md](docs/safety.md). In short:

| Tier | Examples | What happens |
|---|---|---|
| allow | reading non-sensitive files, window/media/volume info, `git status`, screenshots, Friday's own helpers (verified by real path) | runs silently |
| ask | installing/removing packages, writing files outside Friday's scratch folder and notes, `git commit`/`push`, killing processes, launching programs, network fetches to unknown hosts, clicking and typing | an approval card shows the **full** command or file change; you have to scroll through it before Allow works; high-risk ones need <kbd>Ctrl</kbd>+<kbd>↵</kbd> or saying "confirm" |
| deny | `sudo`/`su`/`pkexec`, disk-wiping tools, credentials and tokens, browser profiles and cookies, SSH/GPG keys, password stores, messenger data, shell history, Friday's own guard, settings and keys | refused, with an explanation |

Other protections:

- **Friday can't switch off its own guard.** The guard, the script that wires it in, Friday's settings and keys, the repo's `.git` and `~/.claude` are write-protected from Claude, by any command. The rest of Friday's code can be changed (you can have Friday work on itself), but only through a high-risk approval card showing the diff.
- **Startup files always ask, at high risk.** Shell rc files, autostart entries, systemd user units, compositor configs and `~/.local/bin`: anything that would run later on its own.
- **Private runtime folder.** Approvals, screenshots and scratch files live under `$XDG_RUNTIME_DIR/friday` (mode 700, owner-checked, symlinks refused), not in shared `/tmp`.
- **No answer means no.** An approval nobody answers within 120 s is denied; if the panel isn't running, everything that would ask is denied.
- **Audit log.** Every decision is written to `brain/audit.log` (mode 600, git-ignored); text Friday types for you is redacted.
- **Pinned installs.** Quickshell source builds are pinned to a tagged commit and verified; the icon font is checked against a SHA-256; the AUR build file is shown to you before it runs.
- **Never touches browser cookies.** Signing in uses Claude Code's own login.

## Known limits (honest list)

- The guard parses shell commands with heuristics. Unusual shell syntax it can't confidently parse is treated as "ask", but a clever enough command could still be classified more leniently than it should be. If you find one, please report it.
- Read-only commands are allowed without asking, which means Claude can read most of your home folder (minus the sensitive paths above). That's what makes it useful; it's also what a prompt injection would try to exploit.
- `friday-usage` calls an undocumented Anthropic endpoint with Claude Code's stored token (read-only, only to `api.anthropic.com`, never logged).
- The neural voice uses an unofficial client for a Microsoft service; it could change or disappear.

## Supported versions

Only the latest commit on `main`. Update with `project-friday update`.
