import std/unittest

import lockme/cli

suite "cli":
  test "default colors":
    let opts = parseOptions(@[])
    check opts.initColor == 0x141e25'u32
    check opts.inputColor == 0x202845'u32
    check opts.inputAltColor == 0x1b3734'u32
    check opts.failColor == 0x3c171f'u32

  test "customColors defaults to false":
    let opts = parseOptions(@[])
    check not opts.customColors

  test "ignoreEmptyPassword defaults to true":
    let opts = parseOptions(@[])
    check opts.ignoreEmptyPassword

  test "devMode defaults to false":
    let opts = parseOptions(@[])
    check not opts.devMode

  test "--dev-mode enables dev escape":
    let opts = parseOptions(@["--dev-mode"])
    check opts.devMode

  test "--allow-empty-password disables ignore":
    let opts = parseOptions(@["--allow-empty-password"])
    check not opts.ignoreEmptyPassword

  test "--ignore-empty-password is accepted (back-compat)":
    let opts = parseOptions(@["--ignore-empty-password"])
    check opts.ignoreEmptyPassword

  test "parse colors":
    let opts = parseOptions(@["--init-color", "0x112233", "--input-color", "0x445566", "--input-alt-color", "0x778899"])
    check opts.initColor == 0x112233'u32
    check opts.inputColor == 0x445566'u32
    check opts.inputAltColor == 0x778899'u32
    check opts.customColors

  test "--input-color sets alternate input color":
    let opts = parseOptions(@["--input-color", "0x445566"])
    check opts.inputColor == 0x445566'u32
    check opts.inputAltColor == 0x445566'u32
    check opts.customColors

  test "reject bad color":
    expect ValueError:
      discard parseOptions(@["--fail-color", "112233"])

  test "ready fd":
    let opts = parseOptions(@["--ready-fd", "9"])
    check opts.hasReadyFd
    check opts.readyFd == 9

  test "rejects negative ready fd":
    expect ValueError:
      discard parseOptions(@["--ready-fd", "-1"])

  test "rejects out-of-range ready fd":
    expect ValueError:
      discard parseOptions(@["--ready-fd", "9999999999"])
