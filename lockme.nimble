# Package
version       = "0.1.0"
author        = "Mason Austin Green"
description   = "A small ext-session-lock-v1 Wayland screen locker"
license       = "MIT"
srcDir        = "src"
bin           = @["lockme"]

# Dependencies
requires "nim >= 2.2.0"
requires "nimkdl >= 2.1.0"

const buildCommand =
  "nim c -d:release --forceBuild:on --opt:size --mm:orc -d:useMalloc " &
  "--passC:-flto=auto --passC:-Wno-free-nonheap-object " &
  "--passL:-flto=auto --passL:-Wno-free-nonheap-object " &
  "--passL:-Wl,--gc-sections --passL:-Wl,-s " &
  "--out:lockme src/lockme.nim"

const configTemplate = "examples/config.kdl"
const userConfigDest = "$HOME/.config/lockme/config.kdl"

task build, "Build lockme":
  exec buildCommand

task installBin, "Install the lockme binary to ~/.local/bin (builds if needed)":
  exec buildCommand
  exec "install -Dm755 lockme ~/.local/bin/lockme"
  # Only drop the example config if the user has none yet.
  exec "sh -c 'test -f " & userConfigDest & " || install -Dm644 " &
    configTemplate & " " & userConfigDest & "'"

task installPam, "Install the default PAM file (minimal: pam_faildelay + pam_unix; no faillock/homed/keyring/fingerprint/smartcard)":
  exec "sudo install -m0644 pam.d/lockme /etc/pam.d/lockme"

task installPamFull, "Install the full PAM file (auth include system-auth; enables homed, keyring, fingerprint, smartcard via system-auth)":
  exec "sudo install -m0644 pam.d/lockme.full /etc/pam.d/lockme"

task deploy, "Build release, install binary, drop default config (if absent), and install minimal PAM config":
  exec buildCommand
  exec "install -Dm755 lockme ~/.local/bin/lockme"
  exec "sh -c 'test -f " & userConfigDest & " || install -Dm644 " &
    configTemplate & " " & userConfigDest & "'"
  exec "sudo install -m0644 pam.d/lockme /etc/pam.d/lockme"

task test, "Run unit tests":
  exec "nim c -r --path:src tests/test_password.nim"
  exec "nim c -r --path:src tests/test_cli.nim"
  exec "nim c -r --path:src tests/test_config.nim"
  exec "nim c -r --path:src tests/test_matrix.nim"

task sizecheck, "Build release and report final binary size":
  exec buildCommand
  exec "size lockme"
  exec "ls -lh lockme"

task regenProtocols, "Regenerate checked-in Wayland protocol stubs from vendored XML":
  exec "scripts/regenerate-protocols.sh"
