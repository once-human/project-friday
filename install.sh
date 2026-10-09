#!/usr/bin/env bash
# Project Friday installer: one command on any Linux desktop. Safe to re-run (that's also how you update).
#
#   curl -fsSL https://raw.githubusercontent.com/once-human/project-friday/main/install.sh | bash
#   ./install.sh                 asks once before using sudo, and before the ~700 MB voice download
#   ./install.sh --yes           no questions: installs everything, voice included
#   ./install.sh --no-voice      skip voice ("Hey Friday"); add it later with: project-friday voice setup
#   ./install.sh --offline=TIER  set up the offline brain without asking: small | balanced | smart | smartest
#   ./install.sh --no-offline    don't offer the offline brain (add it later: project-friday offline setup)
#   ./install.sh --no-deps       don't install system packages (just link Friday in)
#   ./install.sh --dry-run       print what would happen, change nothing
#
# What it does:
#   1. works out your distro, package manager and desktop (Hyprland, Sway, niri, KDE, GNOME, XFCE, X11, …)
#   2. installs what's missing with your package manager: Quickshell (the UI toolkit), Claude Code, clipboard,
#      screenshot, media and audio tools, the icon font
#   3. links ~/.config/quickshell/friday -> <repo>/shell and ~/.local/share/friday -> <repo>/brain
#   4. hooks Friday into your desktop: keyboard shortcut, autostart, app-menu entries
#   5. optionally sets up voice, then starts Friday
# Your own files (me.md, memory/, config.env, …) live in <repo>/brain and are git-ignored.
set -euo pipefail

REPO_URL="https://github.com/once-human/project-friday"
# pinned third-party downloads (bump deliberately, together with the checksum/commit)
QS_TAG="v0.3.2"; QS_COMMIT="4f508be500dea6e5732cc3d50382a0048b17e7b1"
FONT_URL="https://raw.githubusercontent.com/google/material-design-icons/49d4db35df873165d6bd6ba09b063c7dafbac2f4/variablefont/MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D.ttf"
FONT_SHA256="32e4011709e055596eb8d2dd0f7cb547b47c1d40ac9ecb8fad54f7f7eac202e7"
YES=0; VOICE=ask; OFFLINE=ask; OFFLINE_MODEL=""; DEPS=1; DRY=0
USER_PATH="$PATH"
for a in "$@"; do
  case "$a" in
    -y|--yes) YES=1 ;;
    --no-voice) VOICE=no ;;
    --voice) VOICE=yes ;;
    --no-offline) OFFLINE=no ;;
    --offline=*) OFFLINE=yes; OFFLINE_MODEL="${a#--offline=}" ;;
    --no-deps) DEPS=0 ;;
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]:-$0}" 2>/dev/null || true; exit 0 ;;
  esac
done

c_say=$'\033[1;38;5;173m'; c_warn=$'\033[1;33m'; c_bad=$'\033[1;31m'; c_dim=$'\033[2m'; c_off=$'\033[0m'
say()  { printf '%s▸%s %s\n' "$c_say" "$c_off" "$*"; }
warn() { printf '%s!%s %s\n' "$c_warn" "$c_off" "$*"; }
die()  { printf '%s✗%s %s\n' "$c_bad" "$c_off" "$*" >&2; exit 1; }
note() { printf '  %s%s%s\n' "$c_dim" "$*" "$c_off"; }
have() { command -v "$1" >/dev/null 2>&1; }
run()  { if [ "$DRY" = 1 ]; then printf '  %s$ %s%s\n' "$c_dim" "$*" "$c_off"; else "$@"; fi; }
ask() {  # ask "question" default(y|n) -> 0 for yes. Works under `curl | bash` too (reads the terminal).
  local q="$1" def="${2:-y}" r=""
  [ "$YES" = 1 ] && return 0
  if [ -r /dev/tty ]; then
    printf '%s?%s %s %s ' "$c_say" "$c_off" "$q" "$([ "$def" = y ] && echo '[Y/n]' || echo '[y/N]')" > /dev/tty
    read -r r < /dev/tty || r=""
  else
    r="$def"
  fi
  r="${r:-$def}"; [[ "$r" =~ ^[Yy] ]]
}

# ---------------------------------------------------------------- 0. platform
case "$(uname -s)" in
  Linux) ;;
  Darwin) die "Friday is a Linux desktop assistant: it lives inside your compositor (Quickshell), which doesn't exist on macOS.
  A native macOS app is on the roadmap. Until then: install Claude Code (curl -fsSL https://claude.ai/install.sh | bash)." ;;
  MINGW*|MSYS*|CYGWIN*|Windows_NT) die "Friday is a Linux desktop assistant and doesn't run on Windows yet (a native app is on the roadmap).
  Claude Code itself works on Windows: irm https://claude.ai/install.ps1 | iex" ;;
  *) die "Unsupported system: $(uname -s). Friday needs Linux with a graphical desktop." ;;
esac
if grep -qi microsoft /proc/version 2>/dev/null && [ "${FRIDAY_FORCE:-}" != 1 ]; then
  die "This is WSL. Friday needs a real Linux desktop session (it draws an overlay inside your compositor), which WSL doesn't have.
  Set FRIDAY_FORCE=1 to install anyway."
fi
[ "$(id -u)" = 0 ] && [ "${FRIDAY_ALLOW_ROOT:-}" != 1 ] && die "Run this as your normal user, not root. It asks for sudo itself when it needs it."

# ---------------------------------------------------------------- 1. get the code (curl | bash, or an old checkout)
SELF="${BASH_SOURCE[0]:-}"
REPO=""
if [ -n "$SELF" ] && [ -f "$SELF" ]; then
  REPO="$(cd "$(dirname "$SELF")" && pwd)"
  [ -d "$REPO/shell" ] && [ -d "$REPO/brain" ] || REPO=""
fi
if [ -z "$REPO" ]; then
  have git || die "git is needed to download Friday. Install git and run this again."
  SRC="${FRIDAY_SRC:-$HOME/.local/src/project-friday}"
  if [ -d "$SRC/.git" ]; then
    say "updating Friday in $SRC"
    run git -C "$SRC" pull --ff-only --quiet || warn "couldn't update $SRC (local changes?); using it as it is"
  else
    say "downloading Friday to $SRC"
    run mkdir -p "$(dirname "$SRC")"
    run git clone --depth 1 --quiet "$REPO_URL" "$SRC"
  fi
  [ "$DRY" = 1 ] && [ ! -d "$SRC" ] && { note "(dry run: would continue with $SRC/install.sh)"; exit 0; }
  exec bash "$SRC/install.sh" "$@"
fi
cd "$REPO"

# ---------------------------------------------------------------- 2. what are we on?
OSR="${FRIDAY_OS_RELEASE:-/etc/os-release}"
ID=""; ID_LIKE=""; PRETTY_NAME="Linux"
# shellcheck disable=SC1090
[ -r "$OSR" ] && . "$OSR"
ids=" ${ID:-} ${ID_LIKE:-} "
case "$ids" in
  *" arch "*|*" archlinux "*|*" manjaro "*|*" endeavouros "*|*" cachyos "*|*" garuda "*) FAM=arch ;;
  *" fedora "*|*" nobara "*|*" ultramarine "*) FAM=fedora ;;
  *" rhel "*|*" centos "*|*" rocky "*|*" almalinux "*) FAM=rhel ;;
  *" debian "*|*" ubuntu "*|*" linuxmint "*|*" pop "*|*" zorin "*|*" elementary "*|*" kali "*|*" raspbian "*) FAM=debian ;;
  *suse*) FAM=suse ;;
  *" void "*) FAM=void ;;
  *" nixos "*) FAM=nixos ;;
  *" gentoo "*) FAM=gentoo ;;
  *" alpine "*) FAM=alpine ;;
  *)
    if have pacman; then FAM=arch; elif have apt-get; then FAM=debian; elif have dnf; then FAM=fedora
    elif have zypper; then FAM=suse; elif have xbps-install; then FAM=void; else FAM=unknown; fi ;;
esac
FAM="${FRIDAY_FAMILY:-$FAM}"
DESK="$(python3 "$REPO/brain/bin/friday-wm" name 2>/dev/null || echo unknown)"
DESK="${FRIDAY_DESKTOP:-$DESK}"
WAYLAND=0; [ -n "${WAYLAND_DISPLAY:-}" ] || [ "${XDG_SESSION_TYPE:-}" = wayland ] && WAYLAND=1
case "$DESK" in x11) WAYLAND=0 ;; hyprland|sway|niri|river|wayfire|labwc|cosmic|wayland) WAYLAND=1 ;; esac
say "Project Friday · $PRETTY_NAME · desktop: $DESK$([ "$WAYLAND" = 1 ] && echo " (Wayland)" || echo "")"

# ---------------------------------------------------------------- 3. system packages
# command -> package, per family ("-" = not packaged there; skip quietly)
pkg() {
  local c="$1"
  case "$FAM:$c" in
    arch:python3) echo python ;;          *:python3) echo python3 ;;
    arch:notify-send) echo libnotify ;;   debian:notify-send) echo libnotify-bin ;; suse:notify-send) echo libnotify-tools ;; *:notify-send) echo libnotify ;;
    arch:wpctl|*:wpctl) echo wireplumber ;;
    arch:pw-record) echo pipewire ;;      debian:pw-record) echo pipewire-bin ;; fedora:pw-record|rhel:pw-record) echo pipewire-utils ;; suse:pw-record) echo pipewire-tools ;; *:pw-record) echo pipewire ;;
    arch:pacat) echo libpulse ;;          void:pacat) echo pulseaudio-utils ;; *:pacat) echo pulseaudio-utils ;;
    arch:nmcli) echo networkmanager ;;    debian:nmcli) echo network-manager ;; *:nmcli) echo NetworkManager ;;
    *:wl-copy) echo wl-clipboard ;;
    *:fc-cache) echo fontconfig ;;
    debian:spectacle) echo kde-spectacle ;;
    rhel:mpv|rhel:yt-dlp|rhel:wtype|rhel:ydotool) echo - ;;
    *) echo "$c" ;;
  esac
}
CORE=(git curl python3 notify-send playerctl wpctl fc-cache)
NICE=(brightnessctl nmcli mpv yt-dlp pacat pw-record)
if [ "$WAYLAND" = 1 ]; then
  CORE+=(wl-copy)
  case "$DESK" in kde|gnome) ;; *) CORE+=(grim) ;; esac
  NICE+=(wtype ydotool)
else
  CORE+=(xclip xdotool)
  NICE+=(maim wmctrl)
fi
[ "$DESK" = gnome ] && NICE+=(gnome-screenshot)
[ "$DESK" = kde ] && NICE+=(spectacle)

missing=()
for c in "${CORE[@]}" "${NICE[@]}"; do have "$c" || missing+=("$c"); done
SUDO=""; [ "$(id -u)" != 0 ] && SUDO="sudo"

pm_install() {  # pm_install pkg… ; returns non-zero if anything failed
  [ $# -eq 0 ] && return 0
  case "$FAM" in
    arch)   run $SUDO pacman -S --needed --noconfirm "$@" ;;
    debian) run $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" ;;
    fedora|rhel) run $SUDO dnf install -y -q "$@" ;;
    suse)   run $SUDO zypper --non-interactive --quiet install "$@" ;;
    void)   run $SUDO xbps-install -Sy "$@" ;;
    *) return 1 ;;
  esac
}

APT_UPDATED=0
apt_update() { [ "$FAM" = debian ] && [ "$APT_UPDATED" = 0 ] && { run $SUDO apt-get update -qq || true; APT_UPDATED=1; }; return 0; }

if [ "$DEPS" = 1 ]; then
  pkgs=()
  for c in "${missing[@]}"; do p="$(pkg "$c")"; [ "$p" != "-" ] && pkgs+=("$p"); done
  # unique
  mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]}" | awk 'NF && !seen[$0]++')
  case "$FAM" in
    arch|debian|fedora|rhel|suse|void)
      if [ ${#pkgs[@]} -gt 0 ]; then
        say "missing tools: ${missing[*]}"
        PMN="$(case "$FAM" in arch) echo pacman ;; debian) echo apt ;; fedora|rhel) echo dnf ;; suse) echo zypper ;; void) echo xbps ;; esac)"
        if ask "Install them with $PMN (uses sudo)?" y; then
          apt_update
          if ! pm_install "${pkgs[@]}"; then
            warn "some packages failed together; trying them one at a time"
            for p in "${pkgs[@]}"; do pm_install "$p" || warn "couldn't install $p (Friday works without it, minus that feature)"; done
          fi
        else
          warn "skipped. Friday will still start; features needing those tools won't work until they're installed."
        fi
      else
        say "system tools: all present"
      fi ;;
    nixos)
      warn "NixOS: add these to environment.systemPackages (or home.packages), then rebuild:"
      note "quickshell git curl python3 libnotify playerctl wireplumber wl-clipboard grim brightnessctl mpv yt-dlp wtype ydotool material-symbols"
      DEPS=0 ;;
    gentoo)
      warn "Gentoo: install with emerge (Quickshell is in the GURU overlay): gui-apps/quickshell gui-apps/wl-clipboard gui-apps/grim media-sound/playerctl x11-libs/libnotify"
      DEPS=0 ;;
    *)
      [ ${#missing[@]} -gt 0 ] && warn "unknown package manager: please install these yourself: ${missing[*]}" ;;
  esac
fi

# ---------------------------------------------------------------- 4. Quickshell (the UI toolkit Friday is built on)
qt_ok() {  # Qt >= 6.6 available?
  local v; v="$(pkg-config --modversion Qt6Core 2>/dev/null || qmake6 -query QT_VERSION 2>/dev/null || echo 0)"
  [ "$v" != 0 ] && printf '6.6\n%s\n' "$v" | sort -V -C
}
build_quickshell() {
  say "building Quickshell from source (a few minutes)"
  local deps=()
  case "$FAM" in
    debian) deps=(build-essential cmake ninja-build pkg-config git qt6-base-dev qt6-base-private-dev qt6-declarative-dev
                  qt6-declarative-private-dev qt6-shadertools-dev qt6-wayland-dev qt6-wayland-private-dev spirv-tools libdrm-dev
                  libcli11-dev libwayland-dev wayland-protocols libxcb1-dev qml6-module-qtquick qml6-module-qtquick-layouts
                  qml6-module-qtquick-shapes qml6-module-qtquick-effects qml6-module-qtquick-window qml6-module-qtqml-workerscript) ;;
    suse)   deps=(cmake ninja gcc-c++ pkgconf git qt6-base-devel qt6-base-private-devel qt6-declarative-devel qt6-declarative-private-devel
                  qt6-shadertools-devel qt6-wayland-devel qt6-wayland-private-devel spirv-tools libdrm-devel cli11-devel wayland-devel
                  wayland-protocols-devel libxcb-devel) ;;
    void)   deps=(base-devel cmake ninja pkg-config git qt6-base-devel qt6-declarative-devel qt6-shadertools-devel qt6-wayland-devel
                  SPIRV-Tools libdrm-devel CLI11 wayland-devel wayland-protocols libxcb-devel) ;;
    rhel)   deps=(cmake ninja-build gcc-c++ pkgconf git qt6-qtbase-devel qt6-qtbase-private-devel qt6-qtdeclarative-devel
                  qt6-qtshadertools-devel qt6-qtwayland-devel spirv-tools libdrm-devel cli11-devel wayland-devel wayland-protocols-devel libxcb-devel) ;;
  esac
  apt_update
  pm_install "${deps[@]}" || { for p in "${deps[@]}"; do pm_install "$p" >/dev/null 2>&1 || true; done; }
  if [ "$DRY" = 0 ] && ! qt_ok; then
    die "your distro's Qt is older than 6.6, which Quickshell needs (Ubuntu 24.04 ships 6.4). Friday needs a newer release
  (Ubuntu 25.04+, Debian 13+, Fedora, Arch, openSUSE Tumbleweed)."
  fi
  local b; b="$(mktemp -d)"
  # a pinned, known release (not "whatever is newest"), checked against its exact commit after cloning
  run git clone --quiet --depth 1 --branch "$QS_TAG" https://github.com/quickshell-mirror/quickshell "$b/quickshell"
  if [ "$DRY" = 0 ] && [ "$(git -C "$b/quickshell" rev-parse HEAD)" != "$QS_COMMIT" ]; then
    rm -rf "$b"; die "Quickshell $QS_TAG didn't match its expected commit; stopping rather than building unknown code."
  fi
  run cmake -GNinja -S "$b/quickshell" -B "$b/build" -DCMAKE_BUILD_TYPE=Release -DCRASH_HANDLER=OFF -DUSE_JEMALLOC=OFF \
      -DSERVICE_PIPEWIRE=OFF -DSERVICE_PAM=OFF -DSERVICE_POLKIT=OFF -DSCREENCOPY=OFF -DSERVICE_STATUS_NOTIFIER=OFF -DSERVICE_MPRIS=OFF
  run cmake --build "$b/build"
  run $SUDO cmake --install "$b/build"
  [ "$DRY" = 0 ] && rm -rf "$b"
  return 0
}
if ! have qs && ! have quickshell; then
  [ "$DEPS" = 1 ] || die "Quickshell isn't installed (and --no-deps / your distro means I can't install it). See docs/install.md."
  say "Quickshell isn't installed: Friday's UI runs on it"
  ask "Install Quickshell now?" y || die "Friday can't run without Quickshell. Re-run when you're ready."
  case "$FAM" in
    arch)
      if have yay; then run yay -S --needed --noconfirm quickshell
      elif have paru; then run paru -S --needed --noconfirm quickshell
      else
        say "no AUR helper found: building the AUR package with makepkg"
        pm_install base-devel git
        tmp="$(mktemp -d)"; run git clone --quiet https://aur.archlinux.org/quickshell.git "$tmp/quickshell"
        if [ "$DRY" = 1 ]; then note "$ (cd $tmp/quickshell && makepkg -si --noconfirm)"
        else
          # AUR packages are user-submitted: show the build script before running it
          say "AUR build script for quickshell (review it):"
          sed 's/^/    /' "$tmp/quickshell/PKGBUILD"
          ask "Build and install it?" y || die "stopped before building Quickshell"
          ( cd "$tmp/quickshell" && makepkg -si --noconfirm )
        fi
        rm -rf "$tmp"
      fi ;;
    fedora) pm_install 'dnf-command(copr)'; run $SUDO dnf copr enable -y errornointernet/quickshell && pm_install quickshell ;;
    debian|suse|void|rhel) build_quickshell ;;
    *) die "please install Quickshell for your distro (https://quickshell.org/docs/master/guide/install-setup/), then run this again." ;;
  esac
  [ "$DRY" = 1 ] || have qs || have quickshell || die "Quickshell didn't install. Scroll up for the error, or see docs/install.md."
  [ "$DRY" = 1 ] || have qs || { warn "Quickshell installed as 'quickshell' only; linking 'qs'"; mkdir -p "$HOME/.local/bin"; ln -sf "$(command -v quickshell)" "$HOME/.local/bin/qs"; }
else
  say "Quickshell: installed"
fi

# ---------------------------------------------------------------- 5. icon font (illogical-impulse ships it; everyone else gets it here)
if ! fc-list 2>/dev/null | grep -qi "Material Symbols Rounded"; then
  say "installing the Material Symbols icon font (Apache 2.0, ~15 MB)"
  FDIR="$HOME/.local/share/fonts/friday"
  run mkdir -p "$FDIR"
  if [ "$DRY" = 1 ]; then note "$ curl -fsSL $FONT_URL  (then check sha256)"
  elif curl -fsSL --retry 3 -o "$FDIR/.MaterialSymbolsRounded.ttf" "$FONT_URL" \
       && echo "$FONT_SHA256  $FDIR/.MaterialSymbolsRounded.ttf" | sha256sum -c --quiet - 2>/dev/null; then
    mv -f "$FDIR/.MaterialSymbolsRounded.ttf" "$FDIR/MaterialSymbolsRounded.ttf"
    fc-cache -f "$FDIR" >/dev/null 2>&1
  else
    rm -f "$FDIR/.MaterialSymbolsRounded.ttf"
    warn "couldn't fetch (or verify) the icon font; icons may show as words until it's installed"
  fi
fi

# ---------------------------------------------------------------- 6. Claude Code (Friday's brain)
export PATH="$HOME/.local/bin:$PATH"
if ! have claude; then
  say "Claude Code isn't installed: Friday thinks with it (needs a Claude Pro/Max/Team/Enterprise or Console account)"
  if ask "Install Claude Code with Anthropic's official installer?" y; then
    if [ "$DRY" = 1 ]; then note "$ curl -fsSL https://claude.ai/install.sh | bash"
    else curl -fsSL https://claude.ai/install.sh | bash || warn "Claude Code install failed; get it from https://code.claude.com/docs"; fi
  else
    warn "skipped: Friday's everyday on-device skills work, anything smarter needs Claude Code"
  fi
else
  say "Claude Code: $(claude --version 2>/dev/null | head -1)"
fi

# ---------------------------------------------------------------- 7. link Friday in
QS="$HOME/.config/quickshell/friday"
DATA="$HOME/.local/share/friday"
STAMP="$(date +%Y%m%d-%H%M%S)"
link() {
  local src="$1" dst="$2"
  if [ -L "$dst" ]; then
    [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ] && { say "ok: $dst"; return; }
    run rm "$dst"
  elif [ -e "$dst" ]; then
    run mv "$dst" "$dst.bak-$STAMP"; say "backed up existing $dst -> $dst.bak-$STAMP"
  fi
  run mkdir -p "$(dirname "$dst")"
  run ln -s "$src" "$dst"; say "linked $dst -> $src"
}
if [ -d "$DATA" ] && [ ! -L "$DATA" ]; then        # carry your private files over from an old copy-style install
  for f in me.md config.env device-profile.md audit.log memory .claude; do
    [ -e "$DATA/$f" ] && [ ! -e "$REPO/brain/$f" ] && { run cp -a "$DATA/$f" "$REPO/brain/$f"; say "kept your $f"; }
  done
fi
link "$REPO/shell" "$QS"
link "$REPO/brain" "$DATA"
if [ "$DRY" = 0 ]; then
  [ -f "$REPO/brain/me.md" ] || { cp "$REPO/brain/me.example.md" "$REPO/brain/me.md"; warn "tell Friday about yourself in $REPO/brain/me.md"; }
  [ -f "$REPO/brain/config.env" ] || cp "$REPO/brain/config.example.env" "$REPO/brain/config.env"
  mkdir -p "$REPO/brain/memory"
  [ -f "$REPO/brain/memory/notes.md" ] || printf '# Notes Friday keeps about how you work\n' > "$REPO/brain/memory/notes.md"
  [ -f "$REPO/brain/device-profile.md" ] || printf '# Device profile\n(not generated yet)\n' > "$REPO/brain/device-profile.md"
  chmod +x "$REPO"/brain/bin/*
fi

# ---------------------------------------------------------------- 8. hook into your desktop
BIN="$DATA/bin"
KEYS_NOTE=""
mark_block() {  # mark_block file "line": add a marked block once (replacing an older one)
  local f="$1" line="$2"
  run mkdir -p "$(dirname "$f")"
  [ -f "$f" ] || run touch "$f"
  if [ "$DRY" = 0 ]; then
    python3 - "$f" "$line" <<'PY'
import re, sys
p, line = sys.argv[1], sys.argv[2]
s = open(p).read()
s = re.sub(r"\n?# >>> friday\n.*?# <<< friday\n?", "\n", s, flags=re.S).rstrip("\n")
open(p, "w").write((s + "\n" if s else "") + "\n# >>> friday\n" + line + "\n# <<< friday\n")
PY
  else
    note "(would add to $f:) $line"
  fi
}
# ---- the command: project-friday (and friday)
run mkdir -p "$HOME/.local/bin"
CLI="$REPO/brain/bin/project-friday"
for n in project-friday friday; do
  dst="$HOME/.local/bin/$n"
  if [ "$n" = friday ]; then
    other="$(PATH="$USER_PATH" command -v friday 2>/dev/null || true)"
    if { [ -e "$dst" ] || [ -L "$dst" ]; } && [ "$(readlink -f "$dst")" != "$(readlink -f "$CLI")" ]; then
      # shellcheck disable=SC2088
      note "~/.local/bin/friday is something else, so the command is just: project-friday"; continue
    fi
    if [ -n "$other" ] && [ "$(readlink -f "$other")" != "$(readlink -f "$CLI")" ] && [ "$other" != "$dst" ]; then
      note "'friday' is already $other, so the command is just: project-friday"; continue
    fi
  fi
  run ln -sfn "$CLI" "$dst"
done
SHORT=""; [ "$(readlink -f "$HOME/.local/bin/friday" 2>/dev/null)" = "$(readlink -f "$CLI")" ] && SHORT=" (or just: friday)"
case ":$USER_PATH:" in
  *":$HOME/.local/bin:"*|*":$HOME/.local/bin/:"*) ;;
  *)
    sh_name="$(basename "${SHELL:-bash}")"
    # shellcheck disable=SC2088
    if ask "~/.local/bin isn't on your PATH, so 'project-friday' won't be found. Add it for $sh_name?" y; then
      case "$sh_name" in
        fish) run mkdir -p "$HOME/.config/fish/conf.d"
              [ "$DRY" = 1 ] || printf '# added by Project Friday\nfish_add_path -g $HOME/.local/bin\n' > "$HOME/.config/fish/conf.d/friday-path.fish" ;;
        zsh)  mark_block "$HOME/.zshrc" 'export PATH="$HOME/.local/bin:$PATH"' ;;
        *)    mark_block "$HOME/.bashrc" 'export PATH="$HOME/.local/bin:$PATH"' ;;
      esac
      note "open a new terminal for it to take effect"
    else
      note "then run it as: ~/.local/bin/project-friday"
    fi ;;
esac

xdg_autostart() {
  run mkdir -p "$HOME/.config/autostart"
  run cp "$REPO/desktop/friday-autostart.desktop" "$HOME/.config/autostart/friday.desktop"
}
systemd_unit() {
  have systemctl || return 1
  run mkdir -p "$HOME/.config/systemd/user"
  run cp "$REPO/desktop/friday.service" "$HOME/.config/systemd/user/friday.service"
  run systemctl --user daemon-reload || true
  run systemctl --user enable friday.service >/dev/null 2>&1 || return 1
}
gnome_keys() {
  have gsettings || return 1
  [ "$DRY" = 1 ] && { note "(would add GNOME shortcuts Super+Alt+Space / +Shift / +Ctrl)"; return 0; }
  python3 - "$BIN" <<'PY'
import ast, subprocess, sys
bin_ = sys.argv[1]
K = "org.gnome.settings-daemon.plugins.media-keys"
base = "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/"
raw = subprocess.run(["gsettings", "get", K, "custom-keybindings"], capture_output=True, text=True).stdout.strip()
cur = ast.literal_eval(raw.replace("@as ", "")) if raw else []
items = [("friday-toggle", "Friday", bin_ + "/friday-toggle", "<Super><Alt>space"),
         ("friday-selection", "Friday on selection", bin_ + "/friday-toggle --selection", "<Shift><Super><Alt>space"),
         ("friday-talk", "Talk to Friday", "qs -c friday ipc call friday listen", "<Primary><Super><Alt>space")]
for key, name, cmd, binding in items:
    path = base + key + "/"
    if path not in cur:
        cur.append(path)
    schema = "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:" + path
    for k, v in (("name", name), ("command", cmd), ("binding", binding)):
        subprocess.run(["gsettings", "set", schema, k, v], check=False)
subprocess.run(["gsettings", "set", K, "custom-keybindings", str(cur)], check=False)
PY
}
xfce_keys() {
  have xfconf-query || return 1
  run xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Super><Alt>space" -n -t string -s "$BIN/friday-toggle"
  run xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Shift><Super><Alt>space" -n -t string -s "$BIN/friday-toggle --selection"
}

case "$DESK" in
  hyprland)
    HYPR="$HOME/.config/hypr"
    if [ -f "$HYPR/custom/rules.conf" ] || [ -d "$HYPR/custom" ]; then
      for f in keybinds.conf execs.conf; do      # older Friday versions wrote inline blocks here
        [ -f "$HYPR/custom/$f" ] && grep -q '^# >>> friday' "$HYPR/custom/$f" && mark_block "$HYPR/custom/$f" "# (moved to rules.conf)"
      done
      mark_block "$HYPR/custom/rules.conf" "source = $REPO/hypr/friday.conf"
    else
      mark_block "$HYPR/hyprland.conf" "source = $REPO/hypr/friday.conf"
    fi
    run hyprctl reload >/dev/null 2>&1 || true
    KEYS_NOTE="Super+Space opens Friday · Super+Shift+Space works on highlighted text · Super+Ctrl+Space to talk" ;;
  sway)
    mark_block "$HOME/.config/sway/config" "include $REPO/desktop/sway.conf"
    run swaymsg reload >/dev/null 2>&1 || true
    KEYS_NOTE="Super+Alt+Space opens Friday · Super+Alt+Shift+Space on highlighted text · Super+Alt+Ctrl+Space to talk" ;;
  gnome)
    xdg_autostart
    gnome_keys && KEYS_NOTE="Super+Alt+Space opens Friday · Super+Alt+Shift+Space on highlighted text · Super+Alt+Ctrl+Space to talk"
    warn "GNOME doesn't support overlay panels on Wayland, so Friday runs there through XWayland (works, but this is the least-tested setup)" ;;
  xfce|x11)
    xdg_autostart
    xfce_keys && KEYS_NOTE="Super+Alt+Space opens Friday · Super+Alt+Shift+Space on highlighted text" ;;
  labwc)
    mark_block "$HOME/.config/labwc/autostart" "$BIN/friday-start &" ;;
  river)
    [ -f "$HOME/.config/river/init" ] && mark_block "$HOME/.config/river/init" "riverctl spawn $BIN/friday-start" ;;
  kde|cosmic|*)
    xdg_autostart
    [ "$DESK" = niri ] || [ "$DESK" = wayfire ] && { systemd_unit || true; } ;;
esac
# app-menu entries + icon on every desktop (search "Friday" in your launcher)
run mkdir -p "$HOME/.local/share/applications" "$HOME/.local/share/icons/hicolor/scalable/apps"
for f in friday friday-selection friday-talk; do run cp "$REPO/desktop/$f.desktop" "$HOME/.local/share/applications/$f.desktop"; done
run cp "$REPO/desktop/friday.svg" "$HOME/.local/share/icons/hicolor/scalable/apps/friday.svg"
have update-desktop-database && run update-desktop-database -q "$HOME/.local/share/applications" 2>/dev/null || true
if [ -z "$KEYS_NOTE" ]; then
  KEYS_NOTE="add a keyboard shortcut in your desktop's settings for:  $BIN/friday-toggle   (and '$BIN/friday-toggle --selection')"
  case "$DESK" in
    kde)  KEYS_NOTE="System Settings → Keyboard → Shortcuts → Add New → Application → \"Friday\" (pick Meta+Alt+Space). Same for \"Friday on selection\"." ;;
    niri) KEYS_NOTE="add to ~/.config/niri/config.kdl inside binds { }:   Mod+Alt+Space { spawn \"$BIN/friday-toggle\"; }" ;;
  esac
fi

# illogical-impulse: Friday in the Super search, the sidebar, and Claude usage in the bar (only if you run ii)
if [ -d "$HOME/.config/quickshell/ii" ]; then
  run "$BIN/friday-integrate" || warn "illogical-impulse hooks skipped; Friday itself still works"
fi

# ---------------------------------------------------------------- 9. voice (optional)
if [ "$VOICE" = ask ]; then
  note "Voice: listening and wake word run 100% on this machine. Friday's natural speaking voice sends the text it speaks"
  note "(never your audio) to Microsoft's speech service; set FRIDAY_TTS=piper in brain/config.env for a fully local voice."
  ask "Set up voice (\"Hey Friday\", talk back)? Downloads ~700 MB of local speech models" y && VOICE=yes || VOICE=no
fi
if [ "$VOICE" = yes ]; then
  if ! have uv; then
    say "installing uv (Python env manager for the speech models)"
    if [ "$DRY" = 1 ]; then note "$ curl -LsSf https://astral.sh/uv/install.sh | sh"; else curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1 || warn "uv install failed; using system Python"; fi
  fi
  run "$BIN/friday-voice-setup" || warn "voice setup failed; run $BIN/friday-voice-setup again later"
fi

# ---------------------------------------------------------------- 9b. offline brain (your pick)
# A free open model (Qwen3, via Ollama) on this laptop, so Friday keeps answering with no internet and when your
# Claude limit runs out. No account, no keys, no limits; nothing leaves the laptop. You choose the size (1.4 to 9 GB).
if [ "$OFFLINE" = ask ] && [ "$YES" = 1 ]; then
  note "Offline brain not set up (--yes never downloads GBs unasked). Add it any time: project-friday offline setup"
  OFFLINE=no
fi
if [ "$OFFLINE" != no ]; then
  say "Offline brain: a free model that runs on this laptop, so Friday works with no internet and no Claude limits"
  OFF_ARGS=()
  [ -n "$OFFLINE_MODEL" ] && OFF_ARGS+=(--model "$OFFLINE_MODEL" --yes)
  [ "$DEPS" = 0 ] && OFF_ARGS+=(--no-install)          # --no-deps: use Ollama if it's there, don't install it
  if [ "$DRY" = 1 ]; then note "$ $BIN/friday-offline-setup ${OFF_ARGS[*]}"
  else "$BIN/friday-offline-setup" "${OFF_ARGS[@]}" || warn "offline brain setup didn't finish; run: project-friday offline setup"; fi
fi

# ---------------------------------------------------------------- 10. start
if [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] && [ "$DRY" = 0 ]; then
  run "$BIN/friday-start" --restart >/dev/null 2>&1 || true
  STARTED=1
else
  STARTED=0
fi
echo
say "Friday is installed$([ "$STARTED" = 1 ] && echo " and running" || echo "; it starts with your next desktop login")."
note "Keys: $KEYS_NOTE"
have claude && ! "$REPO/brain/bin/friday-login" --check 2>/dev/null | grep -q ok && note "First time? Friday shows a Sign in card; or run: claude"
note "Everything else is one command$SHORT: project-friday status · restart · update · help"
[ "$DESK" = hyprland ] || note "Best experience: Arch + Hyprland + illogical-impulse (see README → Recommended setup)"
