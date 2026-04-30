import std/[parseutils, strutils]

const Version* = "0.1.0"

type
  LogLevel* = enum
    llError, llWarning, llInfo, llDebug

  Options* = object
    forkOnLock*: bool
    readyFd*: int
    hasReadyFd*: bool
    ignoreEmptyPassword*: bool
    devMode*: bool
    customColors*: bool
    initColor*: uint32
    inputColor*: uint32
    inputAltColor*: uint32
    failColor*: uint32
    logLevel*: LogLevel
    checkProtocols*: bool
    showHelp*: bool
    showVersion*: bool

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
  --check-protocols                Check required Wayland globals without locking.

  --init-color 0xRRGGBB            Set a solid initial color.
  --input-color 0xRRGGBB           Set a solid color used after input.
  --input-alt-color 0xRRGGBB       Set a solid alternate input color.
  --fail-color 0xRRGGBB            Set a solid auth failure color.
"""

proc defaultOptions*(): Options =
  Options(
    readyFd: -1,
    ignoreEmptyPassword: true,
    initColor: 0x141e25'u32,
    inputColor: 0x202845'u32,
    inputAltColor: 0x1b3734'u32,
    failColor: 0x3c171f'u32,
    logLevel: llError
  )

proc parseColor*(raw: string): uint32 =
  if raw.len != 8 or raw[0..1] != "0x":
    raise newException(ValueError, "invalid color '" & raw & "', expected 0xRRGGBB")
  var value: int
  if parseHex(raw[2..^1], value) != 6:
    raise newException(ValueError, "invalid color '" & raw & "', expected 0xRRGGBB")
  result = uint32(value)

proc parseLogLevel(raw: string): LogLevel =
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
    of "--ignore-empty-password":
      result.ignoreEmptyPassword = true
    of "--allow-empty-password":
      result.ignoreEmptyPassword = false
    of "--dev-mode":
      result.devMode = true
    of "--check-protocols":
      result.checkProtocols = true
    of "--ready-fd":
      let raw = needValue(args, i, arg)
      let fd = parseInt(raw)
      if fd < 0 or fd > int(high(cint)):
        raise newException(ValueError, "invalid --ready-fd value '" & raw & "'")
      result.readyFd = fd
      result.hasReadyFd = true
      inc i
    of "--log-level":
      result.logLevel = parseLogLevel(needValue(args, i, arg))
      inc i
    of "--init-color":
      result.initColor = parseColor(needValue(args, i, arg))
      result.customColors = true
      inc i
    of "--input-color":
      let color = parseColor(needValue(args, i, arg))
      result.inputColor = color
      result.inputAltColor = color
      result.customColors = true
      inc i
    of "--input-alt-color":
      result.inputAltColor = parseColor(needValue(args, i, arg))
      result.customColors = true
      inc i
    of "--fail-color":
      result.failColor = parseColor(needValue(args, i, arg))
      result.customColors = true
      inc i
    else:
      raise newException(ValueError, "unknown option '" & arg & "'")
    inc i
