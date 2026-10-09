# Installing Friday

```bash
curl -fsSL https://raw.githubusercontent.com/once-human/project-friday/main/install.sh | bash
```

That's the whole install on supported setups. This page explains what it does, what's recommended, and how to install by hand.

## Recommended setup

**Arch Linux (or an Arch-based distro) + Hyprland + [illogical-impulse](https://github.com/end-4/dots-hyprland).**

That's what Friday is designed and tested on. You get everything:
- the frosted-glass panel on the focused monitor;
- <kbd>Super</kbd>+<kbd>Space</kbd>;
- full window context, clicking and typing;
- the "Ask Friday" row in ii's Super search, the *Friday* model in ii's AI sidebar, and Claude usage rings in ii's bar.

Hyprland without ii is a close second: everything except those three ii hooks.

## Requirements

- Linux with a graphical session (Wayland or X11). Not WSL, macOS or Windows (yet).
- A Claude **Pro, Max, Team, Enterprise or Console** account for Claude Code. The free plan doesn't include Claude Code.
- About 100 MB of disk, plus about 700 MB if you set up voice.

## What the installer does

| Step | Details |
|---|---|
| Detect | Distro family from `/etc/os-release` (Arch, Fedora, Debian/Ubuntu, openSUSE, Void, RHEL-likes, NixOS, Gentoo) and your desktop (`friday-wm name`). |
| Packages | Asks once, then installs what's missing with your package manager: `git curl python3 libnotify playerctl wireplumber fontconfig`, plus `wl-clipboard grim wtype ydotool` on Wayland or `xclip xdotool maim wmctrl` on X11, and `mpv yt-dlp brightnessctl networkmanager` plus the PipeWire/Pulse tools for voice. If a package doesn't exist on your distro, it's skipped and Friday works without that feature. |
| Quickshell | Arch: AUR `quickshell` (via yay/paru, or makepkg if you have neither). Fedora: COPR `errornointernet/quickshell`. Debian/Ubuntu, openSUSE, Void, RHEL-likes: built from source with the latest release tag (needs Qt ≥ 6.6). NixOS/Gentoo: prints what to add. |
| Icon font | Material Symbols Rounded (Apache 2.0) into `~/.local/share/fonts/friday`, if you don't already have it (illogical-impulse ships it). |
| Claude Code | Anthropic's official installer (`curl -fsSL https://claude.ai/install.sh \| bash`) if `claude` isn't installed. |
| Link | `~/.config/quickshell/friday → <repo>/shell`, `~/.local/share/friday → <repo>/brain`. Your personal files (`me.md`, `memory/`, `config.env`, `device-profile.md`) live in `brain/` and are git-ignored. |
| Desktop | Shortcut, autostart and app-menu entries (search "Friday" in your launcher). See the table below. |
| Voice | Optional: `friday-voice-setup` (Python env via `uv`, Vosk, Whisper `small.en`, Piper, the neural voice packages). |
| Start | `friday-start --restart`. From then on it starts at login and restarts itself if it crashes. |

Run it again any time: it's idempotent, and it's also how you update (`git pull && ./install.sh`).

### Per desktop

| Desktop | Shortcut | Autostart | Notes |
|---|---|---|---|
| Hyprland | <kbd>Super</kbd>+<kbd>Space</kbd>, set automatically (`hypr/friday.conf`, sourced from `custom/rules.conf` on ii or `hyprland.conf` otherwise) | `exec-once` | blur rules included |
| Sway | <kbd>Super</kbd>+<kbd>Alt</kbd>+<kbd>Space</kbd>, set automatically (`include desktop/sway.conf`) | `exec` in that include | Super+Space is Sway's own focus toggle, so Friday doesn't take it |
| niri | add one line (printed by the installer) | systemd user unit (`graphical-session.target`) | |
| river · labwc | add one line · (printed) | init / autostart script | |
| KDE Plasma | System Settings → Keyboard → Shortcuts → Add New → Application → *Friday* | XDG autostart | install `kdotool` for window titles |
| GNOME | <kbd>Super</kbd>+<kbd>Alt</kbd>+<kbd>Space</kbd>, set automatically (custom shortcut) | XDG autostart | experimental: runs through XWayland (GNOME has no layer-shell) |
| XFCE | <kbd>Super</kbd>+<kbd>Alt</kbd>+<kbd>Space</kbd>, set automatically | XDG autostart | |
| Other X11 (Cinnamon, MATE, i3, …) | bind `~/.local/share/friday/bin/friday-toggle` yourself | XDG autostart | |

## Manual install

```bash
git clone https://github.com/once-human/project-friday ~/Projects/project-friday
cd ~/Projects/project-friday
./install.sh --no-deps            # links + desktop hooks only; install the packages above yourself
```

Then bind a key to `~/.local/share/friday/bin/friday-toggle` (and `friday-toggle --selection` for highlighted text), and make sure `~/.local/share/friday/bin/friday-start` runs at login.

## Updating, stopping, removing

```bash
cd <repo> && git pull && ./install.sh     # update
~/.local/share/friday/bin/friday-start --restart   # restart after editing things
~/.local/share/friday/bin/friday-start --stop      # stop until next login
./uninstall.sh            # remove every hook Friday added (your brain/ files stay)
./uninstall.sh --voice    # ...and delete the ~700 MB of speech models
```

## Troubleshooting the install

- **"Qt is older than 6.6"**: Quickshell needs Qt 6.6+. Ubuntu 24.04 ships 6.4; use Ubuntu 25.04+, Debian 13+, Fedora, Arch or Tumbleweed.
- **Icons show as words** (e.g. "mic", "history"): the icon font didn't install. Re-run the installer, or install *Material Symbols Rounded* yourself.
- **No shortcut on KDE / niri / river**: those need the one manual step in the table above.
- **Panel doesn't appear**: run `qs -c friday` in a terminal to see why. See also [troubleshooting.md](troubleshooting.md).
