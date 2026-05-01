import std/[options, unittest]

import lockme/cli

suite "cli":
  test "default colors":
    let opts = parseOptions(@[])
    check opts.initColor == 0x000000'u32
    check opts.failColor == 0x8B0000'u32
    check opts.inputColors == @[0x4B0082'u32, 0x003366'u32, 0x006400'u32]

  test "ignoreEmptyPassword defaults to true":
    let opts = parseOptions(@[])
    check opts.ignoreEmptyPassword

  test "devMode defaults to false":
    let opts = parseOptions(@[])
    check not opts.devMode

  test "--dev-mode enables dev escape":
    let opts = parseOptions(@["--dev-mode"])
    check opts.devMode
    check cfDevMode in opts.setFlags

  test "--allow-empty-password disables ignore":
    let opts = parseOptions(@["--allow-empty-password"])
    check not opts.ignoreEmptyPassword
    check cfIgnoreEmptyPassword in opts.setFlags

  test "--ignore-empty-password is accepted (back-compat)":
    let opts = parseOptions(@["--ignore-empty-password"])
    check opts.ignoreEmptyPassword

  test "parse init/fail colors":
    let opts = parseOptions(@["--init-color", "0x112233", "--fail-color", "0x445566"])
    check opts.initColor == 0x112233'u32
    check opts.failColor == 0x445566'u32
    check cfInitColor in opts.setFlags
    check cfFailColor in opts.setFlags

  test "single --input-color replaces palette":
    let opts = parseOptions(@["--input-color", "0x445566"])
    check opts.inputColors == @[0x445566'u32]
    check cfInputColors in opts.setFlags

  test "repeated --input-color appends after replacing default":
    let opts = parseOptions(@["--input-color", "0x111111", "--input-color", "0x222222", "--input-color", "0x333333"])
    check opts.inputColors == @[0x111111'u32, 0x222222'u32, 0x333333'u32]

  test "reject bad color":
    expect ValueError:
      discard parseOptions(@["--fail-color", "112233"])

  test "reject hash color (CLI requires 0x prefix)":
    expect ValueError:
      discard parseOptions(@["--init-color", "#112233"])

  test "ready fd":
    let opts = parseOptions(@["--ready-fd", "9"])
    check opts.hasReadyFd
    check opts.readyFd == 9
    check cfReadyFd in opts.setFlags

  test "rejects negative ready fd":
    expect ValueError:
      discard parseOptions(@["--ready-fd", "-1"])

  test "rejects out-of-range ready fd":
    expect ValueError:
      discard parseOptions(@["--ready-fd", "9999999999"])

  test "--config sets configPath":
    let opts = parseOptions(@["--config", "/tmp/lockme.kdl"])
    check opts.configPath == some("/tmp/lockme.kdl")
    check cfConfigPath in opts.setFlags

  test "--no-config sets noConfig":
    let opts = parseOptions(@["--no-config"])
    check opts.noConfig
    check cfNoConfig in opts.setFlags

  test "setFlags empty when no overrides":
    let opts = parseOptions(@[])
    check opts.setFlags == {}
