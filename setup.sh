#!/usr/bin/env bash
#
# writerdeck/setup.sh
#
# Turns a fresh, vanilla Debian (console-only) install into a distraction-free
# "writerdeck", inspired by Veronica Explains' build:
#   https://veronicaexplains.net/my-first-writerdeck/
#
# What it does:
#   * Installs kmscon (a modern KMS/DRM console with TTF fonts, >16 colors and
#     Ctrl-+/Ctrl-- zoom), tmux, NetworkManager and your editor of choice.
#   * Configures passwordless autologin into tty1 via kmscon.
#   * Drops you straight into tmux running your editor on boot.
#
# The script is interactive (it asks for editor, font and keyboard layout) and
# idempotent (safe to run more than once). Non-interactive use is possible via
# the WD_* environment variables documented in the README.
#
# Run on a FRESH Debian as a normal user that has sudo rights:
#   bash <(curl -fsSL https://raw.githubusercontent.com/rojacome/writerdeck/main/setup.sh)
#
set -euo pipefail

# --------------------------------------------------------------------------- #
# Pretty logging
# --------------------------------------------------------------------------- #
if [ -t 1 ]; then
  BOLD="$(printf '\033[1m')"; DIM="$(printf '\033[2m')"; RESET="$(printf '\033[0m')"
  BLUE="$(printf '\033[34m')"; GREEN="$(printf '\033[32m')"; YELLOW="$(printf '\033[33m')"; RED="$(printf '\033[31m')"
else
  BOLD=""; DIM=""; RESET=""; BLUE=""; GREEN=""; YELLOW=""; RED=""
fi
say()  { printf '%s\n' "${BLUE}${BOLD}::${RESET} ${BOLD}$*${RESET}"; }
ok()   { printf '%s\n' "${GREEN}  ✓${RESET} $*"; }
warn() { printf '%s\n' "${YELLOW}  !${RESET} $*"; }
die()  { printf '%s\n' "${RED}${BOLD}✗ $*${RESET}" >&2; exit 1; }

# --------------------------------------------------------------------------- #
# Preflight checks
# --------------------------------------------------------------------------- #
[ "$(id -u)" -ne 0 ] || die "Run this as your normal user (NOT root). It will call sudo when needed."
command -v sudo >/dev/null 2>&1 || die "sudo is not installed. On Debian: install sudo and add your user to the sudo group, then re-run."
command -v apt-get >/dev/null 2>&1 || die "This script targets Debian/apt-based systems."

TARGET_USER="$(id -un)"
TARGET_HOME="$HOME"

say "writerdeck setup for user ${BOLD}${TARGET_USER}${RESET}"
echo

# Keep sudo warm for the duration of the run.
sudo -v || die "Could not obtain sudo privileges."
( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap '[ -n "${SUDO_KEEPALIVE_PID:-}" ] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

# --------------------------------------------------------------------------- #
# Interactive choices (with WD_* env overrides for non-interactive use)
# --------------------------------------------------------------------------- #
ask_choice() {
  # ask_choice <prompt> <default-index> <option1> <option2> ...
  local prompt="$1" def="$2"; shift 2
  local opts=("$@") i choice
  if [ ! -t 0 ]; then echo "$def"; return; fi
  printf '%s\n' "${BOLD}${prompt}${RESET}" >&2
  for i in "${!opts[@]}"; do
    printf '   %s) %s\n' "$((i+1))" "${opts[$i]}" >&2
  done
  while true; do
    printf '%s' "  choice [${def}]: " >&2
    read -r choice || true
    choice="${choice:-$def}"
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#opts[@]}" ]; then
      echo "$choice"; return
    fi
    warn "Please enter a number between 1 and ${#opts[@]}." >&2
  done
}

# ---- Editor -------------------------------------------------------------- #
EDITOR_CHOICE="${WD_EDITOR:-}"
if [ -z "$EDITOR_CHOICE" ]; then
  EDITOR_CHOICE="$(ask_choice "Which editor do you want as your writing environment?" 1 \
    "neovim + vimwiki  (a personal wiki, like Veronica's build)" \
    "micro             (modern, friendly terminal editor)" \
    "nano              (simple and ubiquitous)")"
fi

# ---- Font ---------------------------------------------------------------- #
FONT_CHOICE="${WD_FONT:-}"
if [ -z "$FONT_CHOICE" ]; then
  FONT_CHOICE="$(ask_choice "Which monospace font should kmscon use?" 1 \
    "Iosevka          (fonts-iosevka)" \
    "JetBrains Mono   (fonts-jetbrains-mono)" \
    "Fira Code        (fonts-firacode)" \
    "DejaVu Sans Mono (fonts-dejavu, usually preinstalled)")"
fi
case "$FONT_CHOICE" in
  1) FONT_PKG="fonts-iosevka";        FONT_NAME="Iosevka" ;;
  2) FONT_PKG="fonts-jetbrains-mono"; FONT_NAME="JetBrains Mono" ;;
  3) FONT_PKG="fonts-firacode";       FONT_NAME="Fira Code" ;;
  4) FONT_PKG="fonts-dejavu";         FONT_NAME="DejaVu Sans Mono" ;;
  *) die "Invalid font choice." ;;
esac

# ---- Font size ----------------------------------------------------------- #
FONT_SIZE="${WD_FONTSIZE:-}"
if [ -z "$FONT_SIZE" ]; then
  if [ -t 0 ]; then
    printf '%s' "${BOLD}Font size in points${RESET} [16]: " >&2
    read -r FONT_SIZE || true
  fi
  FONT_SIZE="${FONT_SIZE:-16}"
fi
[[ "$FONT_SIZE" =~ ^[0-9]+$ ]] || die "Font size must be a number."

# ---- Keyboard layout ----------------------------------------------------- #
KEYMAP_CHOICE="${WD_KEYMAP:-}"
if [ -z "$KEYMAP_CHOICE" ]; then
  KEYMAP_CHOICE="$(ask_choice "Which keyboard layout should the console use?" 1 \
    "us         (US English)" \
    "us-intl    (US International, dead keys for accents)" \
    "br-abnt2   (Brazilian ABNT2)" \
    "other      (type it yourself)")"
fi
XKB_VARIANT=""
case "$KEYMAP_CHOICE" in
  1) XKB_LAYOUT="us" ;;
  2) XKB_LAYOUT="us"; XKB_VARIANT="intl" ;;
  3) XKB_LAYOUT="br"; XKB_VARIANT="abnt2" ;;
  4|other)
     if [ -t 0 ]; then
       printf '%s' "  xkb layout (e.g. us, br, de): " >&2; read -r XKB_LAYOUT || true
       printf '%s' "  xkb variant (optional, e.g. intl, abnt2): " >&2; read -r XKB_VARIANT || true
     fi
     XKB_LAYOUT="${XKB_LAYOUT:-us}" ;;
  *) XKB_LAYOUT="${KEYMAP_CHOICE}" ;;  # allow passing a raw layout via WD_KEYMAP
esac

echo
say "Summary"
case "$EDITOR_CHOICE" in
  1) echo "  Editor   : neovim + vimwiki" ;;
  2) echo "  Editor   : micro" ;;
  3) echo "  Editor   : nano" ;;
  *) die "Invalid editor choice." ;;
esac
echo "  Font     : ${FONT_NAME} (${FONT_PKG}), size ${FONT_SIZE}"
echo "  Keyboard : ${XKB_LAYOUT}${XKB_VARIANT:+ (variant: ${XKB_VARIANT})}"
echo "  Autologin: ${TARGET_USER} on tty1 via kmscon"
echo
if [ -t 0 ]; then
  printf '%s' "${BOLD}Proceed?${RESET} [Y/n]: "
  read -r confirm || true
  case "${confirm:-y}" in [nN]*) die "Aborted by user." ;; esac
fi

# --------------------------------------------------------------------------- #
# Install packages
# --------------------------------------------------------------------------- #
PKGS=(kmscon tmux network-manager "$FONT_PKG")
case "$EDITOR_CHOICE" in
  1) PKGS+=(neovim git) ;;
  2) PKGS+=(micro) ;;
  3) PKGS+=(nano) ;;
esac

say "Updating package lists"
sudo apt-get update -y
say "Installing: ${PKGS[*]}"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${PKGS[@]}"
ok "Packages installed"

# --------------------------------------------------------------------------- #
# Helper: back up a file once before we overwrite it
# --------------------------------------------------------------------------- #
backup() {
  local f="$1"
  if [ -e "$f" ] && [ ! -e "${f}.writerdeck.bak" ]; then
    sudo cp -a "$f" "${f}.writerdeck.bak" 2>/dev/null || cp -a "$f" "${f}.writerdeck.bak"
    warn "Backed up ${f} -> ${f}.writerdeck.bak"
  fi
}

# --------------------------------------------------------------------------- #
# kmscon.conf
# --------------------------------------------------------------------------- #
say "Writing /etc/kmscon/kmscon.conf"
backup /etc/kmscon/kmscon.conf
sudo mkdir -p /etc/kmscon
{
  echo "# Managed by writerdeck/setup.sh"
  echo "font-name=${FONT_NAME}"
  echo "font-size=${FONT_SIZE}"
  echo "xkb-layout=${XKB_LAYOUT}"
  [ -n "$XKB_VARIANT" ] && echo "xkb-variant=${XKB_VARIANT}"
  # Calm, easy-on-the-eyes palette. Change to 'default' if you prefer.
  echo "palette=solarized"
} | sudo tee /etc/kmscon/kmscon.conf >/dev/null
ok "kmscon configured"

# --------------------------------------------------------------------------- #
# Make kmscon own tty1 instead of the classic getty
# --------------------------------------------------------------------------- #
say "Switching tty1 from getty to kmscon"
sudo systemctl disable --now getty@tty1.service 2>/dev/null || true
sudo systemctl enable kmsconvt@tty1.service
ok "kmsconvt@tty1 enabled"

# --------------------------------------------------------------------------- #
# Passwordless autologin override
# --------------------------------------------------------------------------- #
say "Configuring passwordless autologin for ${TARGET_USER}"
# Derive the distro's default ExecStart and replace its /bin/login call with an
# autologin one, so we stay compatible across kmscon versions.
BASE_EXEC="$(systemctl cat kmsconvt@tty1.service 2>/dev/null | grep -m1 '^ExecStart=' | sed 's/^ExecStart=//')"
if [ -z "$BASE_EXEC" ]; then
  BASE_EXEC='-/usr/bin/kmscon "--vt=%I" --seats=seat0 --no-switchvt --login -- /bin/login -p'
fi
NEW_EXEC="$(printf '%s' "$BASE_EXEC" | sed -E "s#/bin/login[^\"]*#/bin/login -f ${TARGET_USER}#")"
sudo mkdir -p /etc/systemd/system/kmsconvt@tty1.service.d
sudo tee /etc/systemd/system/kmsconvt@tty1.service.d/autologin.conf >/dev/null <<EOF
# Managed by writerdeck/setup.sh
[Service]
ExecStart=
ExecStart=${NEW_EXEC}
EOF
sudo systemctl daemon-reload
ok "Autologin configured"

# --------------------------------------------------------------------------- #
# NetworkManager (so 'nmtui' works for Wi-Fi/hotspots)
# --------------------------------------------------------------------------- #
say "Enabling NetworkManager"
sudo systemctl enable NetworkManager.service >/dev/null 2>&1 || true
ok "NetworkManager enabled (use 'nmtui' to connect to Wi-Fi)"

# --------------------------------------------------------------------------- #
# Editor configuration + on-boot launch command
# --------------------------------------------------------------------------- #
say "Configuring editor"
case "$EDITOR_CHOICE" in
  1) # neovim + vimwiki
     mkdir -p "$TARGET_HOME/.config/nvim" "$TARGET_HOME/vimwiki"
     VW_DIR="$TARGET_HOME/.local/share/nvim/site/pack/writerdeck/start/vimwiki"
     if [ ! -d "$VW_DIR" ]; then
       mkdir -p "$(dirname "$VW_DIR")"
       git clone --depth 1 https://github.com/vimwiki/vimwiki.git "$VW_DIR" \
         || warn "Could not clone vimwiki (no network?). Install it later with: git clone https://github.com/vimwiki/vimwiki ${VW_DIR}"
     fi
     cat > "$TARGET_HOME/.config/nvim/init.vim" <<'NVIMEOF'
" Managed by writerdeck/setup.sh
set nocompatible
filetype plugin indent on
syntax on
set mouse=a
set linebreak              " wrap on word boundaries
set wrap
set number
" Spell check. Change 'en_us' to 'pt' (or 'pt_br') for Portuguese.
set spell spelllang=en_us
" vimwiki, stored as Markdown under ~/vimwiki
let g:vimwiki_list = [{'path': '~/vimwiki/', 'syntax': 'markdown', 'ext': '.md'}]
NVIMEOF
     LAUNCH='nvim +VimwikiIndex'
     ok "neovim + vimwiki ready (~/vimwiki)"
     ;;
  2) # micro
     mkdir -p "$TARGET_HOME/writing"
     [ -f "$TARGET_HOME/writing/index.md" ] || printf '# Writing\n\n' > "$TARGET_HOME/writing/index.md"
     LAUNCH='micro ~/writing/index.md'
     ok "micro ready (~/writing)"
     ;;
  3) # nano
     mkdir -p "$TARGET_HOME/writing"
     [ -f "$TARGET_HOME/writing/index.md" ] || printf '# Writing\n\n' > "$TARGET_HOME/writing/index.md"
     # A couple of writer-friendly nano defaults.
     if ! grep -q 'writerdeck' "$TARGET_HOME/.nanorc" 2>/dev/null; then
       cat >> "$TARGET_HOME/.nanorc" <<'NANOEOF'
# writerdeck defaults
set softwrap
set autoindent
set tabstospaces
NANOEOF
     fi
     LAUNCH='nano ~/writing/index.md'
     ok "nano ready (~/writing)"
     ;;
esac

# --------------------------------------------------------------------------- #
# tmux status bar
# --------------------------------------------------------------------------- #
say "Writing ~/.tmux.conf"
backup "$TARGET_HOME/.tmux.conf"
cat > "$TARGET_HOME/.tmux.conf" <<'TMUXEOF'
# Managed by writerdeck/setup.sh
set -g mouse on
set -g default-terminal "xterm-256color"
set -g history-limit 10000
set -g base-index 1
setw -g pane-base-index 1

# A calm, minimal status bar.
set -g status on
set -g status-interval 5
set -g status-justify left
set -g status-style "bg=default,fg=default"
set -g status-left "#[bold] writerdeck #[default]"
set -g status-left-length 20
set -g status-right "#[fg=cyan]%a %d %b #[fg=white]%H:%M "
set -g window-status-current-style "bold"
TMUXEOF
ok "tmux status bar configured"

# --------------------------------------------------------------------------- #
# Auto-start tmux + editor on tty1 login (via ~/.bashrc)
# --------------------------------------------------------------------------- #
say "Adding auto-start hook to ~/.bashrc"
BRC="$TARGET_HOME/.bashrc"
touch "$BRC"
# Remove any previous writerdeck block so re-runs stay clean.
if grep -q '# >>> writerdeck >>>' "$BRC"; then
  sed -i '/# >>> writerdeck >>>/,/# <<< writerdeck <<</d' "$BRC"
fi
cat >> "$BRC" <<BRCEOF
# >>> writerdeck >>>
# On the main console (tty1), drop straight into tmux + editor.
if [ -z "\${TMUX:-}" ] && [ "\$(tty)" = "/dev/tty1" ]; then
  exec tmux new-session '${LAUNCH}'
fi
# <<< writerdeck <<<
BRCEOF
ok "Auto-start hook installed"

# --------------------------------------------------------------------------- #
# Done
# --------------------------------------------------------------------------- #
echo
say "${GREEN}writerdeck setup complete!${RESET}"
cat <<EOF

  On the next boot you will be logged in automatically on the main console,
  with tmux launching your editor. No desktop, no distractions.

  Handy commands once you're in:
    nmtui            connect to Wi-Fi / hotspots
    Ctrl-+ / Ctrl--  zoom the console font (kmscon)
    tmux             you're already inside it; prefix is Ctrl-b

  A reboot is recommended now to land in the writerdeck.
EOF

if [ -t 0 ]; then
  printf '%s' "${BOLD}Reboot now?${RESET} [y/N]: "
  read -r r || true
  case "${r:-n}" in [yY]*) sudo reboot ;; esac
fi
