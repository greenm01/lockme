# lockme

A hardened, minimalist screen locker for Wayland compositors that
implement `ext-session-lock-v1`.

![Matrix rain lock screen](matrix_rain.png?v=20260502)

`lockme` aims at one thing: keep a typed password out of every place
the kernel and userspace would otherwise let it leak.

The password buffer is page-aligned, `mlock`'d, marked
`MADV_DONTDUMP`, and wiped with `explicit_bzero` on every clear. The
locker process drops dumpability, denies new privileges, and
suppresses core dumps. PAM runs in a forked child that talks back
over a length-prefixed pipe, so a misbehaving auth module never
shares an address space with your secret.

The UI defaults to GPU-rendered Matrix rain while idle. Typing switches to a
solid configurable palette, failed auth shows a solid failure color, and `Alt-B`
toggles between Matrix and a blank screen. Colors and the rest of the runtime
knobs live in a small KDL 2.0 config file (see [Configuration](#configuration)).

It is small on disk too: a stripped release binary is **~430 KB**,
roughly half the size of `hyprlock` and several times smaller than
`waylock` while shipping more hardening than either. See
[compare.md](compare.md) for the full security and size comparison
against `swaylock`, `waylock`, and `hyprlock`.

Press Alt-B to toggle between a blank screen and the matrix rainfall.

## Why

I was missing waylock on the Niri window manager and decided to write a
new one from scratch &mdash; and because I dig Nim.

## Install build dependencies

`lockme` needs Nim/Nimble, a C toolchain, and development headers for
Wayland, Wayland EGL, EGL/GLESv2, xkbcommon, PAM, FreeType, and fontconfig.

Void Linux:

```sh
sudo xbps-install -Sy nim nimble base-devel wayland-devel libglvnd-devel libxkbcommon-devel pam-devel freetype-devel fontconfig-devel pkg-config
```

Arch Linux:

```sh
sudo pacman -S --needed nim nimble base-devel wayland libglvnd libxkbcommon pam freetype2 fontconfig pkgconf
```

Debian/Ubuntu:

```sh
sudo apt update
sudo apt install nim nimble build-essential libwayland-dev libegl-dev libgles-dev libxkbcommon-dev libpam0g-dev libfreetype-dev libfontconfig-dev pkg-config
```

## Build

Build dependencies:

- Nim `2.2.0` or newer
- a C compiler
- `pkg-config`
- development packages for `wayland-client`, `xkbcommon`, `pam`,
  `freetype2`, `fontconfig`, `egl`, `glesv2`, and `wayland-egl`

Protocol refresh dependency:

- `wayland-scanner`

```sh
nimble build
```

Release builds use checked-in Wayland protocol stubs, so `wayland-scanner`
and `wayland-protocols` are not required unless you are refreshing those
generated files.

## Deploy

```sh
nimble deploy
```

This builds an optimized release, installs `lockme` to `~/.local/bin/lockme`,
and installs the PAM service file to `/etc/pam.d/lockme`. The binary install
runs as your user; the PAM install uses `sudo` because `/etc/pam.d` is
root-owned.

## Check compositor compatibility

```sh
lockme --check-protocols
```

At runtime, the compositor must advertise:

- `ext_session_lock_manager_v1`
- `wp_viewporter`
- either `wl_shm` or `wp_single_pixel_buffer_manager_v1`

`wl_shm` is used for the default color surfaces when available.
`wp_single_pixel_buffer_manager_v1` is optional and is used for solid-color
buffers when available.

## Wayland protocol sources

`lockme` uses `libwayland-client` directly through a small C shim and
generated protocol stubs. It does not depend on a third-party Wayland wrapper
library; this keeps the C/Nim boundary explicit and leaves protocol handling
on the standard Wayland C stack.

The generated protocol files are checked in under `src/lockme/protocols`.
Their XML sources are vendored in `src/lockme/protocols/xml`:

- `ext-session-lock-v1` from `wayland-protocols/staging`
- `single-pixel-buffer-v1` from `wayland-protocols/staging`
- `viewporter` from `wayland-protocols/stable`
- `xdg-shell` from `wayland-protocols/stable`

To refresh the generated C/header files after updating the XML:

```sh
nimble regenProtocols
```

Refreshing protocols requires `wayland-scanner`. The task regenerates C/H
from the vendored XML only; update the XML from `wayland-protocols` first
when intentionally moving to a newer protocol revision. Commit the XML and
generated C/H changes together.

## Run

```sh
lockme
```

Plain `lockme` shows Matrix rain while idle and ignores the Enter key on an
empty password buffer. Pass `--blank` to start on a blank screen, or
`--allow-empty-password` if you need empty submissions to reach PAM.

For development only, `lockme --dev-mode` makes `Esc` unlock and exit cleanly
without talking to PAM. This is intentionally insecure and should not be used
for a real screen lock, but it provides a compositor-safe escape hatch while
testing lockme itself.

For screenshots while developing the Matrix renderer, use:

```sh
lockme --dev-mode --dev-window
```

This opens the Matrix rain in a normal Wayland window and does not lock the
session or start PAM.

Matrix rain is rendered through a Sokol/EGL/GLES path when available. The glyph
atlas is generated from the configured font and the built-in Koine Greek Matrix
glyph list; if GPU setup fails, lockme warns and falls back to the existing
software renderer. The GPU rain pipeline adapts MIT-licensed shader logic from
Rezmason's Matrix rain renderer. While locked, `Alt-B` toggles between Matrix
rain and a blank screen.

Typing rotates the surface through a configurable input palette, and failed
authentication shows a solid failure color. The `--init-color`, `--input-color`
(repeatable), and `--fail-color` flags override the defaults.

### Default palette

| State            | Color       | RGB        |
| ---------------- | ----------- | ---------- |
| At rest (`init`) | Black       | `0x000000` |
| Typing (Father)  | Indigo      | `0x4B0082` |
| Typing (Son)     | Royal Blue  | `0x003366` |
| Typing (Spirit)  | Life Green  | `0x006400` |
| Auth failure     | Crimson     | `0x8B0000` |

Repeating `--input-color` defines a custom palette. The first occurrence
replaces the built-in palette; later occurrences append:

```sh
lockme --input-color 0x111111 --input-color 0x222222 --input-color 0x333333
```

## Configuration

`lockme` reads an optional KDL 2.0 configuration file. The discovery order is:

1. `--config <path>` (must exist if specified),
2. `$XDG_CONFIG_HOME/lockme/config.kdl` (default `~/.config/lockme/config.kdl`),
3. each `$XDG_CONFIG_DIRS/lockme/config.kdl` in order (default `/etc/xdg`).

`--no-config` disables the search entirely. CLI flags always win over values
set in the config file. Parse and validation errors abort startup with a
diagnostic on stderr.

A documented template lives at `examples/lockme.kdl` and is dropped into
`~/.config/lockme/config.kdl` by `nimble installBin`/`nimble deploy` only if
that file does not already exist. Both `0xRRGGBB` and `#RRGGBB` color forms
are accepted in the config file (the CLI requires the `0x` form).

## Build size

The release build uses size-oriented flags (`--opt:size --mm:orc
-d:useMalloc -flto -Wl,--gc-sections -Wl,-s`) so that the KDL parser
and its transitive dependencies (`bigints`, `unicodedb`) do not bloat
the binary. The current stripped output is ~430 KB. Run `nimble
sizecheck` to print the size of your build.

## Platform requirements

`lockme` is Linux-only. It relies on the following Linux-specific facilities
to harden the password buffer and the auth child:

- `mlock(2)` and `madvise(MADV_DONTDUMP)` on a page-aligned password buffer,
  preventing it from being paged to swap or included in core dumps.
- `mlockall(2)` on the locker process and auth child to keep transient
  password material on the stack and in libc/PAM internals out of swap. Matrix
  mode and the auth child use `MCL_CURRENT` to avoid turning later GPU, driver,
  or PAM allocations into `RLIMIT_MEMLOCK` failures; `--blank` uses
  `MCL_CURRENT | MCL_FUTURE` in the locker process (best-effort; requires
  sufficient `RLIMIT_MEMLOCK`).
- `explicit_bzero(3)` (glibc/musl) for password clearing that the compiler
  is not permitted to elide.
- `prctl(PR_SET_DUMPABLE, 0)` on both the parent and the auth child to
  block ptrace and `/proc` snooping by other processes of the same UID.
- `prctl(PR_SET_NO_NEW_PRIVS, 1)` on the parent after the PAM auth child is
  forked, so future parent-side `execve` cannot gain privileges without
  breaking PAM helpers such as `unix_chkpwd`.
- `setrlimit(RLIMIT_CORE, 0)` to suppress core dumps for the locker.
- `close_range(2)` (kernel 5.9+) in the auth child to drop inherited file
  descriptors before invoking PAM; falls back to a manual loop on older
  kernels.

## Security

`lockme` mirrors waylock's privilege-separation model: the parent process
holds the Wayland connection and renders the lock surface, while a forked
child performs PAM authentication over a length-prefixed pipe. The
password buffer:

- has a fixed `1024`-byte capacity rounded up to a page,
- is allocated via `posix_memalign` and `mlock`'d for its lifetime,
- is excluded from core dumps via `madvise(MADV_DONTDUMP)`,
- is zeroed via `explicit_bzero` on every clear (including after each
  failed authentication and after each `Backspace`),
- has its protections re-applied after `--fork-on-lock`.

The auth child also re-applies best-effort `mlockall(MCL_CURRENT)` before
initializing PAM, because memory locks are not inherited across `fork(2)`.

With `--fork-on-lock`, the background process additionally redirects
`stdin`/`stdout`/`stderr` to `/dev/null` to avoid `SIGPIPE` if the parent
shell is closed.

`RLIMIT_MEMLOCK` must be at least the password buffer size (one page); the
systemd default of `8M` is more than sufficient for both the password
buffer's `mlock` and the process-wide `mlockall`. If `mlockall` fails
(for example in restrictive containers) a warning is printed but the
locker continues with the password buffer's own `mlock` still active.

## PAM stack

`lockme` performs authentication through PAM. The shipped default
`pam.d/lockme` is a minimal, auditable, distribution-independent chain:

```
auth        optional      pam_faildelay.so delay=2000000
auth        required      pam_unix.so     nullok
account     required      pam_unix.so
```

This verifies a plain Unix password and applies a two-second failure delay
without recording faillock tallies or locking the user out after mistyped
passwords. Most Linux users authenticate this way and gain nothing from a
larger PAM stack on their screen locker, so this is the default.

The default does NOT enable `pam_systemd_home`, GNOME Keyring or
KWallet auto-unlock, fingerprint readers, smartcards, or any other
auxiliary auth method. If you need any of those, install the full PAM
file instead:

```sh
nimble installPamFull
# or, without nimble:
sudo install -m 0644 pam.d/lockme.full /etc/pam.d/lockme
```

The full file contains a single line, `auth include system-auth`, which
delegates authentication to the distribution's `system-auth` chain.
This is the same approach `waylock` and most other screen lockers ship
with. The trade-off is that `lockme`'s effective auth surface becomes
whatever `system-auth` says it is. To audit it, read
`/etc/pam.d/system-auth`; edits there (for example a debugging
`auth sufficient pam_permit.so` line, or a `pam_succeed_if` clause that
bypasses checks for a group) silently affect `lockme` as well, and
`lockme` cannot defend against this.

For PAM debugging, run `./lockme --log-level debug` from a terminal. Debug
logging records PAM status codes and messages only; it does not log password
contents, password length, or prompts.

To revert to the default minimal chain at any time:

```sh
nimble installPam
```
