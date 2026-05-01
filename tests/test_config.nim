import std/[os, unittest]

import lockme/[cli, config]

suite "config":
  test "parseColorString accepts 0x form":
    check parseColorString("0x112233") == 0x112233'u32

  test "parseColorString accepts # form":
    check parseColorString("#aabbcc") == 0xaabbcc'u32

  test "parseColorString rejects bare hex":
    expect ValueError:
      discard parseColorString("112233")

  test "parseColorString rejects truncated hex":
    expect ValueError:
      discard parseColorString("0x123")

  test "parseColorString rejects invalid characters":
    expect ValueError:
      discard parseColorString("0xZZZZZZ")

  test "missing keys preserve defaults":
    let path = getTempDir() / "lockme_test_empty.kdl"
    writeFile(path, "// empty config\n")
    defer: removeFile(path)
    var opts = defaultOptions()
    opts.applyConfigFile(path)
    check opts.initColor == 0x000000'u32
    check opts.failColor == 0x8B0000'u32
    check opts.inputColors == @[0x4B0082'u32, 0x003366'u32, 0x006400'u32]

  test "config sets all colors":
    let path = getTempDir() / "lockme_test_colors.kdl"
    writeFile(path, """
init-color "0x111111"
fail-color "#222222"
inputs {
    color "0x333333"
    color "#444444"
}
""")
    defer: removeFile(path)
    var opts = defaultOptions()
    opts.applyConfigFile(path)
    check opts.initColor == 0x111111'u32
    check opts.failColor == 0x222222'u32
    check opts.inputColors == @[0x333333'u32, 0x444444'u32]

  test "single-color palette is allowed":
    let path = getTempDir() / "lockme_test_single.kdl"
    writeFile(path, """
inputs { color "0xabcdef" }
""")
    defer: removeFile(path)
    var opts = defaultOptions()
    opts.applyConfigFile(path)
    check opts.inputColors == @[0xabcdef'u32]

  test "empty inputs block is rejected":
    let path = getTempDir() / "lockme_test_empty_inputs.kdl"
    writeFile(path, "inputs {}\n")
    defer: removeFile(path)
    var opts = defaultOptions()
    expect ValueError:
      opts.applyConfigFile(path)

  test "invalid hex raises ValueError":
    let path = getTempDir() / "lockme_test_bad.kdl"
    writeFile(path, """init-color "nope"
""")
    defer: removeFile(path)
    var opts = defaultOptions()
    expect ValueError:
      opts.applyConfigFile(path)

  test "CLI overrides win over config":
    let path = getTempDir() / "lockme_test_override.kdl"
    writeFile(path, """init-color "0xaaaaaa"
inputs { color "0xbbbbbb" }
fail-color "0xcccccc"
""")
    defer: removeFile(path)
    var opts = parseOptions(@["--init-color", "0x999999"])
    opts.applyConfigFile(path)
    # CLI-set field stays
    check opts.initColor == 0x999999'u32
    # Unset fields take config values
    check opts.inputColors == @[0xbbbbbb'u32]
    check opts.failColor == 0xcccccc'u32

  test "log-level and booleans":
    let path = getTempDir() / "lockme_test_misc.kdl"
    writeFile(path, """
log-level "debug"
fork-on-lock #true
ignore-empty-password #false
""")
    defer: removeFile(path)
    var opts = defaultOptions()
    opts.applyConfigFile(path)
    check opts.logLevel == llDebug
    check opts.forkOnLock == true
    check opts.ignoreEmptyPassword == false

  test "missing --config path raises":
    var opts = parseOptions(@["--config", "/nonexistent/lockme.kdl"])
    expect ValueError:
      opts.loadConfig()

  test "--no-config short-circuits loadConfig":
    var opts = parseOptions(@["--no-config"])
    opts.loadConfig()  # must not raise even if no file exists
    check opts.initColor == 0x000000'u32
