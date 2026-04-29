# lockme

`lockme` is a small Nim screen locker for Wayland compositors that support
`ext-session-lock-v1`.

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
lockme --ignore-empty-password
```

The v1 UI follows waylock's minimal model: the lock surface is a solid color,
typing changes the color, and failed authentication changes it to the failure
color.
