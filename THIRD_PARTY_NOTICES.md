# Third-party notices

Project Friday's own code is MIT-licensed (see [LICENSE](LICENSE)). It stands on other people's work, listed below with their licenses. Only the items marked **bundled** are shipped in this repository; everything else is installed or downloaded on your machine by `install.sh` / `friday-voice-setup` from its official source, under its own license, and you can inspect or remove it.

If you think something here is wrong or missing, please open an issue.

## Bundled in this repository

| What | Where | License |
|---|---|---|
| [Source Serif 4](https://github.com/adobe-fonts/source-serif) (Adobe) | `shell/assets/fonts/*.woff` | SIL Open Font License 1.1, full text in `shell/assets/fonts/OFL-SourceSerif4.txt` |

## Installed or downloaded on your machine

| What | Used for | License | Notes |
|---|---|---|---|
| [Claude Code](https://claude.com/claude-code) (Anthropic) | the brain: every request Friday can't answer on-device | Proprietary, [Anthropic's terms](https://www.anthropic.com/legal) | Installed with Anthropic's own installer. You need your own Claude account; your use is governed by your agreement with Anthropic. |
| [Quickshell](https://quickshell.org) | draws the panel | LGPL-3.0 | From your distro, the AUR, a COPR, or built from source at a pinned commit. Friday is a configuration for it and doesn't modify it. |
| [Material Symbols Rounded](https://github.com/google/material-design-icons) (Google) | icons | Apache-2.0 | Downloaded at a pinned commit and checked against a SHA-256. |
| [Vosk](https://alphacephei.com/vosk/) + `vosk-model-small-en-in` | local "Hey Friday" wake word and live words | Apache-2.0 | Runs offline. |
| [faster-whisper](https://github.com/SYSTRAN/faster-whisper) (SYSTRAN) | local speech-to-text | MIT | Uses OpenAI [Whisper](https://github.com/openai/whisper) model weights (MIT), converted for CTranslate2, downloaded from Hugging Face. |
| [edge-tts](https://github.com/rany2/edge-tts) | natural neural voice, when online | LGPL-3.0 (one file MIT) | An unofficial client for Microsoft Edge's online read-aloud service. Not affiliated with or endorsed by Microsoft; the service could change or stop at any time, and the text being spoken is sent to it. Turn it off with `FRIDAY_TTS=piper`. |
| [pyminiaudio](https://github.com/irmen/pyminiaudio) | decoding the neural voice's audio | MIT | |
| [Piper](https://github.com/OHF-Voice/piper1-gpl) (`piper-tts`) | offline voice | GPL-3.0-or-later | Installed as a separate Python package in Friday's own virtualenv and run as its own program; Friday doesn't include or link its code. |
| Piper voice **Jenny (Dioco)** (`en_GB-jenny_dioco-medium`) | the default offline voice | [Jenny TTS dataset terms](https://github.com/dioco-group/jenny-tts-dataset): commercial use allowed, attribution required | Attribution: the offline voice is "Jenny (Dioco)". |
| [uv](https://github.com/astral-sh/uv) (Astral) | installing the voice packages quickly | MIT or Apache-2.0 | Optional; falls back to the system Python. |
| [mpv](https://mpv.io), [yt-dlp](https://github.com/yt-dlp/yt-dlp) | background music | GPL-2.0+/LGPL-2.1+ (mpv), Unlicense (yt-dlp) | From your distro's packages. |
| Desktop tools: `grim`, `slurp`, `wl-clipboard`, `playerctl`, `brightnessctl`, `wtype`, `ydotool`, `xdotool`, `xclip`, `jq`, … | screenshots, clipboard, media, input | their own (mostly MIT/GPL) | From your distro's packages. |

## Services Friday talks to

Not software Friday ships, but you should know where data goes:

| Service | When | What it receives |
|---|---|---|
| Anthropic (via Claude Code) | every request that isn't answered on-device, and the weekly phrase refresh (one small Haiku call) | your request, the desktop context Friday attaches (focused window title, clipboard/selection preview when relevant), screenshots you ask about, and tool output |
| Your backup model, if you set one up (Google Gemini API, Groq, OpenRouter; Ollama stays on your laptop) | only when Claude's usage limit is reached or Claude is overloaded | the same as Anthropic would: your request, Friday's instructions with `me.md` and its notes, desktop context, and command output/screenshots for the actions it takes. Each provider's own terms apply; Google's free tier may use it to improve its products. |
| `api.anthropic.com/api/oauth/usage` | the usage rings | Claude Code's local login token, read-only, to fetch your plan usage. Undocumented endpoint. |
| Microsoft's speech service (via edge-tts) | spoken answers, when online and `FRIDAY_TTS` isn't `piper` | the text being read aloud |
| [wttr.in](https://wttr.in) | "what's the weather" | the place you asked about (or your IP's rough location) |
| YouTube (via yt-dlp / your browser) | music | the search terms (built from your request and, for vague requests, your music taste) |
| Hugging Face, alphacephei.com, GitHub, your distro's mirrors | install / voice setup only | ordinary downloads |

## Trademarks

"Claude" and "Claude Code" are trademarks of Anthropic, PBC. "Microsoft" and "Edge" are trademarks of Microsoft Corporation. "Google", "YouTube" and "Material Symbols" are trademarks of Google LLC. All other names are the property of their owners. Project Friday is an independent personal project and is not affiliated with, sponsored by or endorsed by any of them.
