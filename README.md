# lockme

`lockme` is a small screen locker for Wayland compositors that support
`ext-session-lock-v1`.

For a security-focused comparison against `swaylock`, `waylock`, and
`hyprlock`, see [compare.md](compare.md).

## Why

I was missing waylock on Niri and decided to create a new one from scratch... and because I dig Nim.

## Install build dependencies

`lockme` needs Nim/Nimble, a C toolchain, and development headers for
Wayland, xkbcommon, and PAM.

Void Linux:

```sh
sudo xbps-install -Sy nim nimble base-devel wayland-devel libxkbcommon-devel pam-devel pkg-config
```

Arch Linux:

```sh
sudo pacman -S --needed nim nimble base-devel wayland libxkbcommon pam pkgconf
```

Debian/Ubuntu:

```sh
sudo apt update
sudo apt install nim nimble build-essential libwayland-dev libxkbcommon-dev libpam0g-dev pkg-config
```

## Build

Build dependencies:

- Nim `2.2.0` or newer
- a C compiler
- `pkg-config`
- development packages for `wayland-client`, `xkbcommon`, and `pam`

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

`wl_shm` is used for the default gradient surfaces when available.
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

Plain `lockme` runs with all hardening enabled and ignores the Enter key on
an empty password buffer. Pass `--allow-empty-password` if you need empty
submissions to reach PAM.

For development only, `lockme --dev-mode` makes `Esc` unlock and exit cleanly
without talking to PAM. This is intentionally insecure and should not be used
for a real screen lock, but it provides a compositor-safe escape hatch while
testing lockme itself.

The v1 UI follows waylock's minimal model: the lock surface is a subtle
gradient, typing changes the gradient, and failed authentication changes it
to the failure gradient. The `--init-color`, `--input-color`,
`--input-alt-color`, and `--fail-color` flags switch the UI back to exact
solid colors for all states.

## Platform requirements

`lockme` is Linux-only. It relies on the following Linux-specific facilities
to harden the password buffer and the auth child:

- `mlock(2)` and `madvise(MADV_DONTDUMP)` on a page-aligned password buffer,
  preventing it from being paged to swap or included in core dumps.
- `mlockall(MCL_CURRENT | MCL_FUTURE)` on the locker process to keep
  transient password material on the stack and in libc internals out of
  swap (best-effort; requires sufficient `RLIMIT_MEMLOCK`).
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
auth        required                 pam_faillock.so preauth
auth        [success=1 default=bad]  pam_unix.so     nullok
auth        [default=die]            pam_faillock.so authfail
auth        sufficient               pam_faillock.so authsucc
account     required      pam_unix.so
```

This verifies a plain Unix password and applies bruteforce backoff via
`pam_faillock` (with tunables inherited from
`/etc/security/faillock.conf`). Most Linux users authenticate this way
and gain nothing from a larger PAM stack on their screen locker, so
this is the default.

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

To revert to the default minimal chain at any time:

```sh
nimble installPam
```
