# writerdeck

Turn a **fresh, vanilla Debian** install into a distraction-free, console-only
**writerdeck** with a single script.

Inspired by Veronica Explains' build:
<https://veronicaexplains.net/my-first-writerdeck/>

The idea: no desktop, no browser, no notifications. You power the machine on and
land directly in a full-screen terminal editor. Just you and the words.

---

## Quick start

On a **freshly installed Debian** (console / "standard system utilities" only —
no desktop needed), logged in as a **normal user with sudo rights**, run:

```bash
bash <(curl -fsSL j4c.me/wd)
```

> **Minimal Debian installs don't include `curl`.** If you get
> `curl: command not found`, use `wget` instead — it's always present:
>
> ```bash
> bash <(wget -qO- j4c.me/wd)
> ```
>
> Once inside, the script will install `curl` automatically before proceeding.

That's it. The script will ask you a few questions and then set everything up.
A reboot drops you straight into your writing environment.

> **Don't run it as root.** Run it as the user you want to auto-login. The script
> calls `sudo` itself when it needs root.
>
> `j4c.me/wd` redirects to:
> `https://raw.githubusercontent.com/rojacome/writerdeck/main/setup.sh`

---

## What the script does

1. **Installs the building blocks**
   - [`kmscon`](https://www.freedesktop.org/wiki/Software/kmscon/) — a modern
     KMS/DRM console that replaces the classic tty. It supports **TrueType
     fonts**, **more than 16 colors**, and **on-the-fly zoom** with
     `Ctrl-+` / `Ctrl--` (like a web browser).
   - `tmux` — gives you a clean status bar (date/time) and terminal multiplexing.
   - `network-manager` — connect to Wi-Fi/hotspots from the console with `nmtui`.
   - Your chosen **editor** and **font**.

2. **Asks you three things** (interactive):
   - **Editor** — `neovim + vimwiki` (a personal wiki, like Veronica's build),
     `micro`, or `nano`.
   - **Font** — Iosevka, JetBrains Mono, Fira Code, or DejaVu Sans Mono (plus a
     font size). See [Fonts](#fonts) below.
   - **Keyboard layout** — `us`, `us-intl`, `br-abnt2`, or a custom layout.

3. **Configures passwordless autologin** on the main console (`tty1`) using a
   systemd drop-in for `kmsconvt@tty1.service` that runs `/bin/login -f <you>`.
   The classic `getty@tty1` is disabled and `kmsconvt@tty1` takes over.

4. **Auto-launches your editor inside tmux** on boot, via a small block added to
   your `~/.bashrc`. For `neovim + vimwiki` it opens straight at your wiki index.

### Files it creates or edits

| Path | Purpose |
| --- | --- |
| `/etc/kmscon/kmscon.conf` | Font, size, keyboard layout, color palette |
| `/etc/systemd/system/kmsconvt@tty1.service.d/autologin.conf` | Passwordless autologin |
| `~/.tmux.conf` | Minimal status bar |
| `~/.config/nvim/init.vim` | neovim + vimwiki config (if chosen) |
| `~/.bashrc` | Auto-start block (between `# >>> writerdeck >>>` markers) |

Existing files are **backed up** to `*.writerdeck.bak` before being changed, and
the script is **idempotent** — running it again won't pile up duplicate config.

---

## After it runs

Once you reboot you're in the writerdeck. A few things to know:

| Command / keys | What it does |
| --- | --- |
| `nmtui` | Connect to Wi-Fi / hotspots |
| `Ctrl-+` / `Ctrl--` | Zoom the console font (kmscon) |
| `Ctrl-b` | tmux prefix (you're already inside tmux) |

- **neovim + vimwiki**: your wiki lives in `~/vimwiki` (Markdown). Inside neovim,
  `Enter` follows/creates links; `:VimwikiIndex` jumps to the index.
- **micro / nano**: a starter file is created at `~/writing/index.md`.

To change the spell-check language in neovim, edit `~/.config/nvim/init.vim` and
set, e.g., `set spell spelllang=pt` for Portuguese.

---

## Non-interactive / unattended install

You can skip the prompts by setting environment variables:

| Variable | Values |
| --- | --- |
| `WD_EDITOR` | `1` = neovim+vimwiki, `2` = micro, `3` = nano |
| `WD_FONT` | `1` = Iosevka, `2` = JetBrains Mono, `3` = Fira Code, `4` = DejaVu Sans Mono |
| `WD_FONTSIZE` | a number, e.g. `16` |
| `WD_KEYMAP` | `1` = us, `2` = us-intl, `3` = br-abnt2 |

Example:

```bash
WD_EDITOR=1 WD_FONT=1 WD_FONTSIZE=18 WD_KEYMAP=3 \
  bash <(curl -fsSL j4c.me/wd)
```

---

## Undoing it

To go back to a normal text console:

```bash
sudo systemctl disable kmsconvt@tty1.service
sudo systemctl enable getty@tty1.service
sudo rm -f /etc/systemd/system/kmsconvt@tty1.service.d/autologin.conf
# remove the block between the "writerdeck" markers in ~/.bashrc
```

Backups of any replaced files are next to the originals as `*.writerdeck.bak`.

---

## Fonts

The four monospace fonts offered by the script. All are free and open source.

| # | Font | Preview / Homepage | Debian package |
| --- | --- | --- | --- |
| 1 | **Iosevka** | [typeof.net/Iosevka](https://typeof.net/Iosevka/) | `fonts-iosevka` |
| 2 | **JetBrains Mono** | [jetbrains.com/lp/mono](https://www.jetbrains.com/lp/mono/) | `fonts-jetbrains-mono` |
| 3 | **Fira Code** | [github.com/tonsky/FiraCode](https://github.com/tonsky/FiraCode) | `fonts-firacode` |
| 4 | **DejaVu Sans Mono** | [dejavu-fonts.github.io](https://dejavu-fonts.github.io/) | `fonts-dejavu` |

> **Tip:** [programmingfonts.org](https://www.programmingfonts.org/) lets you
> preview and compare all of them side by side with your own text.

---

## Notes & credit

- Tested against **Debian 13 (Trixie)**. Should work on recent Debian releases
  that ship `kmscon`.
- All credit for the concept and the original walkthrough goes to
  **Veronica Explains** — see the
  [post](https://veronicaexplains.net/my-first-writerdeck/) and the
  [FAQ](https://veronicaexplains.net/writerdeck-faq/).

## License

MIT — see [`LICENSE`](LICENSE).
