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
    defer:
      removeFile(path)
    var opts = defaultOptions()
    opts.applyConfigFile(path)
    check opts.initColor == 0x000000'u32
    check opts.failColor == 0x8B0000'u32
    check opts.inputColors == @[0x4B0082'u32, 0x003366'u32, 0x006400'u32]

  test "config sets all colors":
    let path = getTempDir() / "lockme_test_colors.kdl"
    writeFile(
      path,
      """
init-color "0x111111"
fail-color "#222222"
inputs {
    color "0x333333"
    color "#444444"
}
""",
    )
    defer:
      removeFile(path)
    var opts = defaultOptions()
    opts.applyConfigFile(path)
    check opts.initColor == 0x111111'u32
    check opts.failColor == 0x222222'u32
    check opts.inputColors == @[0x333333'u32, 0x444444'u32]

  test "single-color palette is allowed":
    let path = getTempDir() / "lockme_test_single.kdl"
    writeFile(
      path,
      """
inputs { color "0xabcdef" }
""",
    )
    defer:
      removeFile(path)
    var opts = defaultOptions()
    opts.applyConfigFile(path)
    check opts.inputColors == @[0xabcdef'u32]

  test "empty inputs block is rejected":
    let path = getTempDir() / "lockme_test_empty_inputs.kdl"
    writeFile(path, "inputs {}\n")
    defer:
      removeFile(path)
    var opts = defaultOptions()
    expect ValueError:
      opts.applyConfigFile(path)

  test "invalid hex raises ValueError":
    let path = getTempDir() / "lockme_test_bad.kdl"
    writeFile(
      path,
      """init-color "nope"
""",
    )
    defer:
      removeFile(path)
    var opts = defaultOptions()
    expect ValueError:
      opts.applyConfigFile(path)

  test "CLI overrides win over config":
    let path = getTempDir() / "lockme_test_override.kdl"
    writeFile(
      path,
      """init-color "0xaaaaaa"
inputs { color "0xbbbbbb" }
fail-color "0xcccccc"
""",
    )
    defer:
      removeFile(path)
    var opts = parseOptions(@["--init-color", "0x999999"])
    opts.applyConfigFile(path)
    # CLI-set field stays
    check opts.initColor == 0x999999'u32
    # Unset fields take config values
    check opts.inputColors == @[0xbbbbbb'u32]
    check opts.failColor == 0xcccccc'u32

  test "log-level and booleans":
    let path = getTempDir() / "lockme_test_misc.kdl"
    writeFile(
      path,
      """
log-level "debug"
fork-on-lock #true
ignore-empty-password #false
""",
    )
    defer:
      removeFile(path)
    var opts = defaultOptions()
    opts.applyConfigFile(path)
    check opts.logLevel == llDebug
    check opts.forkOnLock == true
    check opts.ignoreEmptyPassword == false

  test "blank option and matrix settings":
    let path = getTempDir() / "lockme_test_blank.kdl"
    writeFile(
      path,
      """
blank #true
matrix-frame-ms 220
matrix-cell-scale 1.5
matrix-fall-speed 0.4
matrix-cycle-speed 0.05
matrix-raindrop-length 1.25
matrix-brightness-decay 1.5
""",
    )
    defer:
      removeFile(path)
    var opts = defaultOptions()
    opts.applyConfigFile(path)
    check opts.blank == true
    check opts.matrixFrameMs == 220
    check opts.matrixCellScale == 1.5
    check opts.matrixFallSpeed == 0.4
    check opts.matrixCycleSpeed == 0.05
    check opts.matrixRaindropLength == 1.25
    check opts.matrixBrightnessDecay == 1.5

  test "legacy matrix font settings are ignored":
    let path = getTempDir() / "lockme_test_legacy_font_settings.kdl"
    writeFile(
      path,
      """
matrix-font-family "JetBrains Mono"
matrix-font-path "/tmp/matrix.ttf"
matrix-font-size 4
matrix-line-height 4
""",
    )
    defer:
      removeFile(path)
    var opts = defaultOptions()
    opts.applyConfigFile(path)
    check opts.matrixCellScale == MatrixCellScaleDefault

  test "matrix-cell-scale auto string selects responsive scale":
    let path = getTempDir() / "lockme_test_matrix_cell_scale_auto.kdl"
    writeFile(path, "matrix-cell-scale \"auto\"\n")
    defer:
      removeFile(path)
    var opts = defaultOptions()
    opts.applyConfigFile(path)
    check opts.matrixCellScale == MatrixCellScaleAuto

  test "matrix-cell-scale zero selects responsive scale":
    let path = getTempDir() / "lockme_test_matrix_cell_scale_zero.kdl"
    writeFile(path, "matrix-cell-scale 0\n")
    defer:
      removeFile(path)
    var opts = defaultOptions()
    opts.applyConfigFile(path)
    check opts.matrixCellScale == MatrixCellScaleAuto

  test "CLI blank wins over config":
    let path = getTempDir() / "lockme_test_blank_override.kdl"
    writeFile(path, "blank #false\n")
    defer:
      removeFile(path)
    var opts = parseOptions(@["--blank"])
    opts.applyConfigFile(path)
    check opts.blank == true

  test "old matrix option is rejected":
    let path = getTempDir() / "lockme_test_matrix_replaced.kdl"
    writeFile(path, "matrix #false\n")
    defer:
      removeFile(path)
    var opts = defaultOptions()
    expect ValueError:
      opts.applyConfigFile(path)

  test "matrix-frame-ms range is validated":
    let path = getTempDir() / "lockme_test_matrix_frame_bad.kdl"
    writeFile(path, "matrix-frame-ms 10\n")
    defer:
      removeFile(path)
    var opts = defaultOptions()
    expect ValueError:
      opts.applyConfigFile(path)

  test "matrix-cell-scale range is validated":
    for value in ["-1", "0.5", "9", "\"manual\""]:
      let path = getTempDir() / "lockme_test_matrix_cell_scale_bad.kdl"
      writeFile(path, "matrix-cell-scale " & value & "\n")
      defer:
        removeFile(path)
      var opts = defaultOptions()
      expect ValueError:
        opts.applyConfigFile(path)

  test "matrix timing ranges are validated":
    for name in [
      "matrix-fall-speed", "matrix-cycle-speed", "matrix-raindrop-length",
      "matrix-brightness-decay",
    ]:
      let path = getTempDir() / ("lockme_test_" & name & "_bad.kdl")
      writeFile(path, name & " 0\n")
      defer:
        removeFile(path)
      var opts = defaultOptions()
      expect ValueError:
        opts.applyConfigFile(path)

  test "missing --config path raises":
    var opts = parseOptions(@["--config", "/nonexistent/lockme.kdl"])
    expect ValueError:
      opts.loadConfig()

  test "--no-config short-circuits loadConfig":
    var opts = parseOptions(@["--no-config"])
    opts.loadConfig() # must not raise even if no file exists
    check opts.initColor == 0x000000'u32

  test "no-gpu config enables CPU-only renderer":
    let path = getTempDir() / "lockme_test_no_gpu.kdl"
    writeFile(path, "no-gpu #true\n")
    defer:
      removeFile(path)
    var opts = defaultOptions()
    opts.applyConfigFile(path)
    check opts.noGpu == true

  test "CLI --no-gpu wins over config no-gpu false":
    let path = getTempDir() / "lockme_test_no_gpu_override.kdl"
    writeFile(path, "no-gpu #false\n")
    defer:
      removeFile(path)
    var opts = parseOptions(@["--no-gpu"])
    opts.applyConfigFile(path)
    check opts.noGpu == true

  test "idle-timeout config sets seconds":
    let path = getTempDir() / "lockme_test_idle_timeout.kdl"
    writeFile(path, "idle-timeout 120\n")
    defer:
      removeFile(path)
    var opts = defaultOptions()
    opts.applyConfigFile(path)
    check opts.idleTimeoutSecs == 120

  test "idle-timeout config rejects negative":
    let path = getTempDir() / "lockme_test_idle_timeout_bad.kdl"
    writeFile(path, "idle-timeout -5\n")
    defer:
      removeFile(path)
    var opts = defaultOptions()
    expect ValueError:
      opts.applyConfigFile(path)
