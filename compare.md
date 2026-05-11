# lockme vs swaylock, waylock, hyprlock

*May 2, 2026*

A side-by-side look at four Wayland screen lockers, written for the user
who has to pick one and live with it.

## The contestants

| Locker   | Language | Version  | LoC (security paths) | Stripped binary |
|----------|----------|----------|----------------------|-----------------|
| swaylock | C        | 1.8.5    | ~820                 | 106 KB          |
| waylock  | Zig      | 1.7.0-dev (HEAD 9523ce0) | ~1,310 | 1.9 MB        |
| hyprlock | C++      | 0.9.5    | ~9,330 (whole tree)  | 825 KB          |
| lockme   | Nim      | 0.1.0    | ~1,300               | 558 KiB         |

Sizes are the as-shipped binaries on the author's Arch system
(`/usr/bin/{swaylock,waylock,hyprlock}` from the official packages and
`nimble build` for lockme). lockme is still well under the size of
hyprlock and several times smaller than waylock, despite shipping more
hardening than either.

All four use `ext-session-lock-v1`. All four call PAM. That is where the
agreement ends.

## The matrix

| Primitive                          | swaylock | waylock | hyprlock | lockme |
|------------------------------------|----------|---------|----------|--------|
| Forked auth child (privilege sep)  | yes      | yes     | **no, threaded** | yes |
| Length-prefixed auth pipe          | yes      | yes     | n/a (in-process) | yes |
| Page-aligned password buffer       | yes      | pointer only | no | yes |
| Allocation rounded up to a page    | no       | no      | no       | yes |
| `mlock` on password buffer         | yes      | yes     | no       | yes |
| `madvise(MADV_DONTDUMP)`           | no       | yes     | no       | yes |
| Non-elidable secure zero           | volatile loop | `secureZero` | `string = ""` (unsafe) | `explicit_bzero` |
| `prctl(PR_SET_DUMPABLE, 0)`        | no       | no      | no       | yes (parent + child) |
| `prctl(PR_SET_NO_NEW_PRIVS, 1)`    | no       | no      | no       | yes (parent after auth fork) |
| `setrlimit(RLIMIT_CORE, 0)`        | no       | no      | no       | yes |
| `mlockall` best effort             | no       | no      | no       | yes (`MCL_CURRENT`; stronger `MCL_FUTURE` only with `--blank`) |
| `close_range` in auth child        | no       | no      | n/a      | yes (with fallback) |
| Default ignores empty Enter        | no       | no      | no       | yes |
| Default PAM stack                  | `auth include login` | `auth include system-auth` | `auth include login` | `pam_faildelay` + `pam_unix` |

## swaylock

The grandfather. Plain C, mature, in every distro. The architecture is
sound: it forks an auth child, talks to it over two pipes with a
length-prefixed protocol, and asserts the trailing NUL on the wire. The
password buffer is page-aligned with `posix_memalign`, `mlock`'d (with
EAGAIN retries and EPERM fallback), and wiped with a volatile-byte
loop. Buffer is destroyed after every authentication attempt.

Where it falls short is everything outside the buffer. No
`MADV_DONTDUMP`. No `PR_SET_DUMPABLE`. No `PR_SET_NO_NEW_PRIVS`. No
core-dump suppression. The shipped PAM file is a one-liner that
includes the system `login` stack, and there is no in-process rate
limiting. Empty Enter goes straight to PAM by default.

The codebase is small and easy to read. Years of distro deployment.
That counts for a lot.

## waylock

Zig, written by someone who clearly knew what he was doing. lockme is
modeled on it. The fork-and-pipe model matches swaylock's, with a tidy
4-byte length prefix and a single-byte reply. The password buffer
allocation is page-aligned by pointer, `mlock`'d with retries, and
wiped with `std.crypto.secureZero`. Crucially, waylock is the only one
of the three reference lockers that calls `madvise(MADV_DONTDUMP)`.

Two gaps stand out. First, the buffer length is `size_max` (1024
bytes), not page-rounded. The kernel locks and marks the entire page
anyway, but the rest of that page can hold neighboring allocator
state. Second, there is no process-wide hardening: no `PR_SET_DUMPABLE`,
no `PR_SET_NO_NEW_PRIVS`, no `RLIMIT_CORE=0`, no `mlockall`, no
`close_range` in the auth child. The child closes its two pipe ends
and that is all.

The PAM file is `auth include system-auth`. Same posture as everyone
else.

## hyprlock

This one is different, and not in a good way for a screen locker.

There is no auth child. PAM runs in a `std::thread` inside the main
hyprlock process (`src/auth/Pam.hpp:44`, `src/auth/Pam.cpp:81-90`).
That means every PAM module the system loads runs in the same address
space as the Wayland connection, the EGL context, the GPU buffers, and
the password itself. A bug in any loaded `.so` reads anything.

The password lives in a `std::string`
(`src/core/hyprlock.hpp:144`). It is not `mlock`'d. It is not
`madvise`'d. It is not page-aligned. It is "cleared" by assigning the
empty string, which does not overwrite the previously-held heap memory.
The PAM conversation callback `strdup`'s the password into a second
heap buffer (`src/auth/Pam.cpp:43`), so during authentication the
secret exists in at least two places, neither protected. There is no
`explicit_bzero`, no `secureZero`, nothing.

No process hardening. No `prctl`. No `setrlimit`. No `mlockall`. The
only memory-related call is `mallopt(M_TRIM_THRESHOLD)`, which is
performance tuning, not hardening.

Hyprlock's GitHub security advisory page is empty. That does not mean
no bypasses — it means the maintainers have not used the advisory
mechanism. The repo we cloned is shallow and history-light, so we
could not enumerate past fixes. But the 9,330-line C++ surface, the
GPU/EGL/dmabuf/screencopy paths, and the in-process threaded PAM all
add up to a much larger attack surface than swaylock or waylock.

If you use hyprlock for anything more serious than a desktop curiosity,
reconsider.

## lockme

Built on the waylock model, then extended. Forked auth child,
length-prefixed pipe, byte reply — same shape as waylock and swaylock.

The password buffer goes further than either of them. Allocation is
page-aligned **and** rounded up to a page multiple, so `mlock` and
`madvise(MADV_DONTDUMP)` cover whole owned pages and nothing leaks
through page granularity. Clearing uses `explicit_bzero` from glibc
or musl, which the compiler is not permitted to elide. `popCodepoint`
zeros the popped bytes specifically, not just the whole buffer.

The process model adds the syscalls waylock left out:

- `prctl(PR_SET_DUMPABLE, 0)` in both parent and auth child.
- `prctl(PR_SET_NO_NEW_PRIVS, 1)` on the parent after the auth child is
  forked, leaving PAM helpers such as `unix_chkpwd` usable.
- `setrlimit(RLIMIT_CORE, 0)` to suppress core dumps.
- `mlockall` best-effort, with debug diagnostics if `RLIMIT_MEMLOCK` is
  too low. The Matrix renderer and auth child use `MCL_CURRENT`; `--blank`
  keeps the stronger parent-side `MCL_CURRENT | MCL_FUTURE` path.
- `close_range` in the auth child to drop inherited file descriptors,
  with a manual fallback for kernels older than 5.9.
- `--fork-on-lock` redirects stdio to `/dev/null` and re-applies the
  buffer protections after the fork.

PAM defaults differ too. The shipped `pam.d/lockme` is the explicit
minimal chain — `pam_faildelay` + `pam_unix`, which slows repeated
failures without recording faillock tallies or locking out the user.
That choice is deliberate for a screen locker: a local attacker should
not be able to turn three bad guesses into a timed lockout of a later
correct password. The full `auth include system-auth` chain is available
as opt-in via `nimble installPamFull` for folks who need fingerprint,
smartcard, homed, or keyring auto-unlock. Empty Enter is ignored by
default; `--allow-empty-password` opens it back up.

The UI changed since the first version of this document. lockme now
defaults to GPU-rendered Matrix rain while idle, with `--blank` and
`Alt-B` available for the solid blank screen. Typing and failure states
still switch to simple solid-color buffers. This is a real usability
feature, but it is also a larger dependency and FFI surface than the
original solid-only build: EGL/GLES and Sokol are now part of the display
path. The Matrix glyphs are built in from a generated alpha source derived from
the vendored CNTR Koine Greek font, so system font updates do not affect
rendering. The main security boundary remains the forked PAM child and
protected password buffer, so the Matrix renderer does not run in the auth
process.

Where lockme is weaker: no formal third-party human review, no fuzzing,
no CI, no distro packaging, single author, and now a new GPU renderer
that needs more time under real compositors. The current AI-assisted
review notes and recent fix history are recorded in [audit.md](audit.md),
but that is not a substitute for years of field exposure. swaylock and
waylock have been deployed across thousands of installs. lockme has not.
Years of accidental field testing is its own kind of audit, and lockme
has not had it yet.

## Verdict

In rough order of "would I trust this on my own machine":

1. **lockme** for the security-conscious single-user Linux workstation,
   given its hardening goes beyond the others and its surface is
   still deliberately narrow around authentication. The disclaimer is
   real: no formal third-party human review, single author, a new GPU
   display path, and no field deployment yet. See [audit.md](audit.md)
   for the current review log.
2. **waylock** for the same use case if you want a project that has
   been deployed by other folks for several years. You give up
   `MADV_DONTDUMP`-on-the-process and the process-wide hardening, but
   you get years of accidental QA.
3. **swaylock** if you want something every distro packages and
   nothing fancy. Solid C, proven, well-understood. Fewer hardening
   bells than waylock or lockme.
4. **hyprlock** only if you accept the threaded PAM and unprotected
   password as a feature, not a bug, in exchange for the GPU
   widgets and animations. For a screen locker, the trade is bad.

NOTE: Most lockers here delegate to a one-line PAM include. Whichever
you pick, audit the PAM chain it actually uses. lockme's default avoids
`system-auth` by design; `nimble installPamFull` opts back into it when
you need distro-integrated auth modules.

## What lockme could still tighten

Roughly in priority:

1. End-to-end test plan against Sway, Niri, and Hyprland, including
   the `--fork-on-lock` and `--ready-fd` paths.
2. CI on glibc and musl. `explicit_bzero`, `close_range`, and
   `MADV_DONTDUMP` portability assumptions need to fail loudly, not
   silently.
3. A `/proc/$pid/status` smoke test asserting `VmLck` non-zero and
   `Dumpable: 0` after startup.
4. A core-dump test: `kill -SEGV` a debug build and grep the dump
   for keystroke bytes.
5. Get independent human review of the C shim layer, the Sokol/EGL
   Matrix renderer, and the FFI declarations.
6. Reproducible builds and signed releases, eventually.
