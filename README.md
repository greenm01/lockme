# lockme

`lockme` is a small Nim screen locker for Wayland compositors that support
`ext-session-lock-v1`.

Tested and verified under the Niri Window Manager.

## Build

```sh
nimble build
```

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

## Run

```sh
lockme
```

Plain `lockme` runs with all hardening enabled and ignores the Enter key on
an empty password buffer. Pass `--allow-empty-password` if you need empty
submissions to reach PAM.

The v1 UI follows waylock's minimal model: the lock surface is a solid color,
typing changes the color, and failed authentication changes it to the failure
color.

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
- `prctl(PR_SET_NO_NEW_PRIVS, 1)` to ensure no future `execve` can gain
  privileges.
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
