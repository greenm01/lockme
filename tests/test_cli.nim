import std/unittest

import lockme/cli

suite "cli":
  test "default colors":
    let opts = parseOptions(@[])
    check opts.initColor == 0x002b36'u32
    check opts.inputColor == 0x6c71c4'u32
    check opts.inputAltColor == 0x6c71c4'u32
    check opts.failColor == 0xdc322f'u32

  test "parse colors":
    let opts = parseOptions(@["--init-color", "0x112233", "--input-color", "0x445566", "--input-alt-color", "0x778899"])
    check opts.initColor == 0x112233'u32
    check opts.inputColor == 0x445566'u32
    check opts.inputAltColor == 0x778899'u32

  test "reject bad color":
    expect ValueError:
      discard parseOptions(@["--fail-color", "112233"])

  test "ready fd":
    let opts = parseOptions(@["--ready-fd", "9"])
    check opts.hasReadyFd
    check opts.readyFd == 9
