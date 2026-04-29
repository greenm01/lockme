# Package
version       = "0.1.0"
author        = "Mason Austin Green"
description   = "A small ext-session-lock-v1 Wayland screen locker for niri"
license       = "MIT"
srcDir        = "src"
bin           = @["lockme"]

# Dependencies
requires "nim >= 2.2.0"

task build, "Build lockme":
  exec "nim c -d:release --out:lockme src/lockme.nim"

task test, "Run unit tests":
  exec "nim c -r --path:src tests/test_password.nim"
  exec "nim c -r --path:src tests/test_cli.nim"
