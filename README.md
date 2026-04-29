# lockme

`lockme` is a small Nim screen locker for Wayland compositors that support
`ext-session-lock-v1`, with niri as the initial target.

## Build

```sh
nimble build
```

## Check niri compatibility

```sh
./lockme --check-protocols
```

## Run

Install `pam.d/lockme` to `/etc/pam.d/lockme`, then run:

```sh
./lockme --ignore-empty-password
```

The v1 UI follows waylock's minimal model: the lock surface is a solid color,
typing changes the color, and failed authentication changes it to the failure
color.
