# Wayland Protocol Sources

The generated `*-client-protocol.h` and `*-protocol.c` files in this
directory are checked in so release builds do not require `wayland-scanner`
or `wayland-protocols`.

The XML files in `xml/` are vendored from `wayland-protocols`:

- `staging/ext-session-lock/ext-session-lock-v1.xml`
- `staging/single-pixel-buffer/single-pixel-buffer-v1.xml`
- `stable/viewporter/viewporter.xml`

To refresh the generated files after updating the XML sources:

```sh
scripts/regenerate-protocols.sh
```

Set `WAYLAND_SCANNER=/path/to/wayland-scanner` to use a non-default scanner.
