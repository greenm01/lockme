import std/[options, parseutils, strutils]

const Version* = "0.1.0"
const MatrixFrameMsDefault* = 40
const MatrixCellScaleDefault* = 2
const MatrixFontFamilyDefault* = "monospace"
const MatrixFontPathDefault* = ""
const MatrixFontSizeDefault* = 18
const MatrixLineHeightDefault* = 24
const MatrixFallSpeedDefault* = 0.3
const MatrixCycleSpeedDefault* = 0.03
const MatrixRaindropLengthDefault* = 0.75
const MatrixBrightnessDecayDefault* = 1.0

type
  LogLevel* = enum
    llError, llWarning, llInfo, llDebug

  CliFlag* = enum
    ## Which option fields were explicitly set on the CLI. Used to merge
    ## defaults <- config-file <- CLI without re-parsing.
    cfForkOnLock
    cfReadyFd
    cfIgnoreEmptyPassword
    cfDevMode
    cfInitColor
    cfInputColors
    cfFailColor
    cfLogLevel
    cfCheckProtocols
    cfConfigPath
    cfNoConfig
    cfMatrix
    cfDevWindow

  Options* = object
    forkOnLock*: bool
    readyFd*: int
    hasReadyFd*: bool
    ignoreEmptyPassword*: bool
    devMode*: bool
    initColor*: uint32
    inputColors*: seq[uint32]
    failColor*: uint32
    logLevel*: LogLevel
    checkProtocols*: bool
    showHelp*: bool
    showVersion*: bool
    configPath*: Option[string]
    noConfig*: bool
    matrix*: bool
    devWindow*: bool
    matrixFrameMs*: int
    matrixCellScale*: int
    matrixFontFamily*: string
    matrixFontPath*: string
    matrixFontSize*: int
    matrixLineHeight*: int
    matrixFallSpeed*: float
    matrixCycleSpeed*: float
    matrixRaindropLength*: float
    matrixBrightnessDecay*: float
    setFlags*: set[CliFlag]

const Usage* = """usage: lockme [options]

  -h, --help                       Print this help message and exit.
  --version                        Print the version number and exit.
  --log-level <level>              Set log level: error, warning, info, debug.

  --fork-on-lock                   Fork to the background after locking.
  --ready-fd <fd>                  Write a newline to fd after locking.
  --allow-empty-password           Submit empty passwords to PAM (default:
                                   ignore Enter on empty buffer).
  --dev-mode                       Insecure development mode: Esc unlocks and
                                   exits without PAM authentication.
  --dev-window                     With --dev-mode, render the Matrix preview
                                   in a normal Wayland window.
  --check-protocols                Check required Wayland globals without locking.
  --matrix                         Enable matrix screensaver when idle.

  --config <path>                  Load configuration from <path>.
  --no-config                      Do not load any configuration file.

  --init-color 0xRRGGBB            Set the at-rest color.
  --input-color 0xRRGGBB           Add an input-state color. Repeatable; the
                                   first occurrence replaces the default
                                   palette, subsequent occurrences append.
                                   lockme cycles through these on each
                                   keypress.
  --fail-color 0xRRGGBB            Set the auth failure color.
"""

proc defaultOptions*(): Options =
  ## Built-in defaults. See README for the documented palette.
  Options(
    readyFd: -1,
    ignoreEmptyPassword: true,
    initColor: 0x000000'u32,                                # pure black
    inputColors: @[0x4B0082'u32, 0x003366'u32, 0x006400'u32], # Father (Tyrian indigo/violet), Son (royal blue), Spirit (life green)
    failColor: 0x8B0000'u32,                                # deep crimson
    logLevel: llError,
    matrixFrameMs: MatrixFrameMsDefault,
    matrixCellScale: MatrixCellScaleDefault,
    matrixFontFamily: MatrixFontFamilyDefault,
    matrixFontPath: MatrixFontPathDefault,
    matrixFontSize: MatrixFontSizeDefault,
    matrixLineHeight: MatrixLineHeightDefault,
    matrixFallSpeed: MatrixFallSpeedDefault,
    matrixCycleSpeed: MatrixCycleSpeedDefault,
    matrixRaindropLength: MatrixRaindropLengthDefault,
    matrixBrightnessDecay: MatrixBrightnessDecayDefault
  )

proc parseColor*(raw: string): uint32 =
  ## Parses a `0xRRGGBB` color literal as used on the CLI.
  if raw.len != 8 or raw[0..1] != "0x":
    raise newException(ValueError, "invalid color '" & raw & "', expected 0xRRGGBB")
  var value: int
  if parseHex(raw[2..^1], value) != 6:
    raise newException(ValueError, "invalid color '" & raw & "', expected 0xRRGGBB")
  result = uint32(value)

proc parseLogLevel*(raw: string): LogLevel =
  case raw
  of "error": llError
  of "warning": llWarning
  of "info": llInfo
  of "debug": llDebug
  else:
    raise newException(ValueError, "invalid log level '" & raw & "'")

proc needValue(args: seq[string]; i: int; opt: string): string =
  if i + 1 >= args.len:
    raise newException(ValueError, "missing value for " & opt)
  args[i + 1]

proc parseOptions*(args: seq[string]): Options =
  result = defaultOptions()
  var inputColorSeen = false
  var i = 0
  while i < args.len:
    let arg = args[i]
    case arg
    of "-h", "--help":
      result.showHelp = true
    of "--version":
      result.showVersion = true
    of "--fork-on-lock":
      result.forkOnLock = true
      result.setFlags.incl cfForkOnLock
    of "--ignore-empty-password":
      result.ignoreEmptyPassword = true
      result.setFlags.incl cfIgnoreEmptyPassword
    of "--allow-empty-password":
      result.ignoreEmptyPassword = false
      result.setFlags.incl cfIgnoreEmptyPassword
    of "--dev-mode":
      result.devMode = true
      result.setFlags.incl cfDevMode
    of "--dev-window":
      result.devWindow = true
      result.setFlags.incl cfDevWindow
    of "--check-protocols":
      result.checkProtocols = true
      result.setFlags.incl cfCheckProtocols
    of "--matrix":
      result.matrix = true
      result.setFlags.incl cfMatrix
    of "--no-config":
      result.noConfig = true
      result.setFlags.incl cfNoConfig
    of "--config":
      result.configPath = some(needValue(args, i, arg))
      result.setFlags.incl cfConfigPath
      inc i
    of "--ready-fd":
      let raw = needValue(args, i, arg)
      let fd = parseInt(raw)
      if fd < 0 or fd > int(high(cint)):
        raise newException(ValueError, "invalid --ready-fd value '" & raw & "'")
      result.readyFd = fd
      result.hasReadyFd = true
      result.setFlags.incl cfReadyFd
      inc i
    of "--log-level":
      result.logLevel = parseLogLevel(needValue(args, i, arg))
      result.setFlags.incl cfLogLevel
      inc i
    of "--init-color":
      result.initColor = parseColor(needValue(args, i, arg))
      result.setFlags.incl cfInitColor
      inc i
    of "--input-color":
      let color = parseColor(needValue(args, i, arg))
      if not inputColorSeen:
        result.inputColors = @[color]
        inputColorSeen = true
      else:
        result.inputColors.add color
      result.setFlags.incl cfInputColors
      inc i
    of "--fail-color":
      result.failColor = parseColor(needValue(args, i, arg))
      result.setFlags.incl cfFailColor
      inc i
    else:
      raise newException(ValueError, "unknown option '" & arg & "'")
    inc i
