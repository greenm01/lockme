# Package
version       = "0.1.0"
author        = "Mason Austin Green"
description   = "A small ext-session-lock-v1 Wayland screen locker"
license       = "MIT"
srcDir        = "src"
bin           = @["lockme"]

# Dependencies
requires "nim >= 2.2.0"

const buildCommand = "nim c -d:release --out:lockme src/lockme.nim"

task build, "Build lockme":
  exec buildCommand

task installBin, "Install the lockme binary to ~/.local/bin (builds if needed)":
  exec buildCommand
  exec "install -Dm755 lockme ~/.local/bin/lockme"

task installPam, "Install the default PAM file (auth include system-auth)":
  exec "sudo install -m0644 pam.d/lockme /etc/pam.d/lockme"

task installPamMinimal, "Install the minimal PAM file (pam_unix + pam_faillock; no homed/keyring/fingerprint/smartcard)":
  exec "sudo install -m0644 pam.d/lockme.minimal /etc/pam.d/lockme"

task deploy, "Build release, install binary, and install default PAM config":
  exec buildCommand
  exec "install -Dm755 lockme ~/.local/bin/lockme"
  exec "sudo install -m0644 pam.d/lockme /etc/pam.d/lockme"

task test, "Run unit tests":
  exec "nim c -r --path:src tests/test_password.nim"
  exec "nim c -r --path:src tests/test_cli.nim"
