# Wayland Protocol Sources

The generated `*-client-protocol.h` and `*-protocol.c` files in this
directory are checked in so release builds do not require `wayland-scanner`
or `wayland-protocols`.

The XML files in `xml/` are vendored from `wayland-protocols`:

- `staging/ext-session-lock/ext-session-lock-v1.xml`
- `staging/single-pixel-buffer/single-pixel-buffer-v1.xml`
- `stable/viewporter/viewporter.xml`
- `stable/xdg-shell/xdg-shell.xml`

To refresh the generated files after updating the XML sources:

```sh
nimble regenProtocols
# or, directly:
scripts/regenerate-protocols.sh
```

Refreshing protocols requires `wayland-scanner`. The command regenerates C/H
from the vendored XML only; update the XML from `wayland-protocols` first
when intentionally moving to a newer protocol revision. Commit the XML and
generated C/H changes together.

Set `WAYLAND_SCANNER=/path/to/wayland-scanner` to use a non-default scanner.
