# Security Audit Notes

**Date:** May 2, 2026

This document records security and performance review notes for `lockme` on
`main`, with the latest reviewed commit at the time of writing:

```text
774ef6e Harden matrix shm buffer sizing
```

It is an engineering review log, not a formal third-party certification.

## Threat Model

The primary threat model is a physical attacker interacting with a locked
Wayland session, without pre-existing code execution as the locked-in user.
The main assets are the typed password, the lock state, and the integrity of
the PAM authentication result.

## Gemini Findings

Gemini's reviews produced several actionable findings. The confirmed issues
were fixed and committed:

- Auth child memory locking: the PAM auth child now performs its own
  best-effort `mlockall(MCL_CURRENT)`, because parent memory locks are not
  inherited across `fork`.
- CPU Matrix renderer hot path: alpha scaling and glyph clipping were
  optimized to remove unnecessary inner-loop division and bounds checks.
- Blank/failure state regression: failed authentication now returns from the
  red failure color to the expected blank or idle state.
- Correct-password failures: PAM status logging showed local `pam_faillock`
  lockout, so the default PAM stack now uses `pam_faildelay` plus `pam_unix`
  instead of a timed faillock policy.
- Opportunistic `mlockall` noise: process-wide `mlockall` failures are now
  debug-only; the dedicated password buffer `mlock` remains mandatory.
- Matrix column allocation churn: Matrix rain resets columns in place and
  reuses preallocated glyph buffers.
- Graceful shutdown: SIGINT and SIGTERM are routed through `signalfd` into the
  main poll loop, allowing normal cleanup.
- Matrix SHM sizing: CPU fallback and preview SHM buffers now use checked
  `int64` layout math, dimension caps, and validated stride/size values before
  `ftruncate`, `mmap`, and `wl_shm_pool_create_buffer`.

Gemini also raised an FD-inheritance concern around `--fork-on-lock`. Review
showed the backgrounded child is the live locker and must keep the Wayland
socket, signal fd, and auth pipes. `readyFd` is written and closed before the
daemonizing fork, and the PAM child closes inherited fds via `closeInheritedFds`.
No code change was needed for that item.

## Claude Opus 4.7 Findings

Claude Opus 4.7 reported no high-confidence vulnerabilities. It verified the
following mitigations as present:

- Auth result protocol accepts only byte `1` as success; failure, EOF, or
  malformed results do not unlock.
- Password transport is length-prefixed and rejects lengths above `SizeMax`
  before reading.
- The password buffer is page-rounded, `mlock`'d, `MADV_DONTDUMP`'d, and
  cleared with `explicit_bzero`.
- Password submission is gated on `lsLocked`, so pre-lock keystrokes cannot be
  submitted to PAM.
- Matrix SHM sizing uses validated bounds and checked byte-size calculations.
- Keymap mmap rejects zero-length and oversized compositor keymaps.
- PAM child fd inheritance is constrained by `closeInheritedFds`.
- xkb UTF-8 key handling drops truncated input and clears the stack buffer.
- The default PAM stack contains no sufficient bypass such as `pam_permit`.
- Config loading does not execute shells or run in a privileged context.
- `--fork-on-lock` parent exit happens before password input is collected.

## GPU Rendering Risks and Mitigations

The GPU matrix renderer introduces risks that the CPU-only path avoids. Users
who want to reduce the attack surface can pass `--no-gpu` or set `no-gpu true`
in the config file, which forces the CPU renderer without requiring a separate
blank-only invocation.

**Compositor trust dependency.** `ext-session-lock-v1` guarantees that if
`lockme` exits without calling `unlock_and_destroy`, the compositor keeps the
screen blacked out. The locker's lock integrity in the crash case therefore
depends on the compositor implementing this guarantee correctly. A SIGSEGV in
the C shim (EGL, Sokol, or the GPU driver) would kill the whole process, and
the compositor — not the locker — would be responsible for maintaining the
locked state. Niri implements this correctly; compositors that do not are not
supported. The `--no-gpu` flag eliminates the largest FFI crash surface for
users who want to remove this dependency.

**GPU VRAM residue.** Intermediate render-to-texture targets (raindrop and
symbol ping-pong buffers) use `SG_LOADACTION_CLEAR` on first use, so they are
zeroed at the Sokol level. GPU drivers are required to zero-initialize memory
across security context boundaries, but driver bugs in this area are a
documented vulnerability class. This risk is not specific to `lockme` and
affects all EGL-using compositing clients.

**EGL/driver attack surface.** The GPU renderer introduces EGL and the Mesa
driver stack as additional code in the process. `lockme` does not run
privileged, so the worst case from a driver bug is a process crash (handled
by the compositor, per the dependency above) rather than privilege escalation.

## Codex Review Notes

The current design keeps the strongest guarantees around the actual password
buffer and PAM boundary:

- PAM runs in a forked child with a minimal length-prefixed pipe protocol.
- Parent-side rendering and Wayland state are separated from PAM module code.
- `PR_SET_DUMPABLE=0`, core dump suppression, `no_new_privs`, and fd cleanup
  reduce same-UID inspection and accidental inheritance.
- Process-wide `mlockall` is treated as defense in depth; failure is visible
  at debug level, while password-buffer `mlock` remains fail-closed.
- The default PAM policy avoids local lockout by using delay-only backoff.

Remaining caveats are operational rather than active findings:

- `lockme` has not had broad third-party review or long distro field exposure.
- The GPU Matrix renderer and C shims remain the largest native/FFI surface.
- PAM behavior still depends on the installed `/etc/pam.d/lockme` file.
- `pam.d/lockme.full` deliberately opts into the broader distribution
  `system-auth` policy and should be audited separately by users who install it.
