## Lockme configuration file loading.
##
## Configuration is parsed from a KDL document and merged into the existing
## Options. CLI flags always win over config (tracked via Options.setFlags).
## Defaults remain in effect for fields neither the config nor the CLI set.

import std/[options, os, parseutils, strutils]
import kdl

import ./cli

const
  ConfigDirName* = "lockme"
  ConfigFileName* = "config.kdl"

proc parseColorString*(raw: string): uint32 =
  ## Accepts both ``0xRRGGBB`` and ``#RRGGBB`` hex literals.
  ## Raises ``ValueError`` for anything else.
  var hex: string
  if raw.len == 8 and raw[0..1] == "0x":
    hex = raw[2..^1]
  elif raw.len == 7 and raw[0] == '#':
    hex = raw[1..^1]
  else:
    raise newException(ValueError,
      "invalid color '" & raw & "', expected 0xRRGGBB or #RRGGBB")
  var value: int
  if parseHex(hex, value) != 6:
    raise newException(ValueError,
      "invalid color '" & raw & "', expected 0xRRGGBB or #RRGGBB")
  uint32(value)

proc xdgConfigHome(): string =
  let env = getEnv("XDG_CONFIG_HOME")
  if env.len > 0: env else: getEnv("HOME") / ".config"

proc xdgConfigDirs(): seq[string] =
  let env = getEnv("XDG_CONFIG_DIRS")
  let raw = if env.len > 0: env else: "/etc/xdg"
  for part in raw.split(':'):
    if part.len > 0:
      result.add part

proc findConfigFile*(): Option[string] =
  ## Searches the standard XDG locations for ``lockme/config.kdl``.
  let primary = xdgConfigHome() / ConfigDirName / ConfigFileName
  if fileExists(primary):
    return some(primary)
  for dir in xdgConfigDirs():
    let path = dir / ConfigDirName / ConfigFileName
    if fileExists(path):
      return some(path)
  none(string)

proc parseLogLevelStrict(raw: string): LogLevel =
  case raw
  of "error": llError
  of "warning": llWarning
  of "info": llInfo
  of "debug": llDebug
  else:
    raise newException(ValueError, "invalid log-level '" & raw & "'")

proc applyConfigDoc*(opts: var Options; doc: KdlDoc) =
  ## Applies values from ``doc`` to ``opts`` only for fields that the CLI
  ## did not explicitly set (per ``opts.setFlags``).
  let initNode = doc.findNode("init-color")
  if initNode.isSome and cfInitColor notin opts.setFlags:
    let n = initNode.get
    if n.args.len < 1:
      raise newException(ValueError, "init-color requires a value")
    opts.initColor = parseColorString(n.args[0].kString())

  let failNode = doc.findNode("fail-color")
  if failNode.isSome and cfFailColor notin opts.setFlags:
    let n = failNode.get
    if n.args.len < 1:
      raise newException(ValueError, "fail-color requires a value")
    opts.failColor = parseColorString(n.args[0].kString())

  let inputsNode = doc.findNode("inputs")
  if inputsNode.isSome and cfInputColors notin opts.setFlags:
    var palette: seq[uint32]
    for child in inputsNode.get.children:
      if child.name != "color":
        raise newException(ValueError,
          "unknown node '" & child.name & "' under inputs (expected 'color')")
      if child.args.len < 1:
        raise newException(ValueError, "inputs.color requires a value")
      palette.add parseColorString(child.args[0].kString())
    if palette.len == 0:
      raise newException(ValueError, "inputs block must contain at least one color")
    opts.inputColors = palette

  let logNode = doc.findNode("log-level")
  if logNode.isSome and cfLogLevel notin opts.setFlags:
    let n = logNode.get
    if n.args.len < 1:
      raise newException(ValueError, "log-level requires a value")
    opts.logLevel = parseLogLevelStrict(n.args[0].kString())

  let forkNode = doc.findNode("fork-on-lock")
  if forkNode.isSome and cfForkOnLock notin opts.setFlags:
    let n = forkNode.get
    if n.args.len < 1:
      raise newException(ValueError, "fork-on-lock requires a boolean value")
    opts.forkOnLock = n.args[0].kBool()

  let emptyNode = doc.findNode("ignore-empty-password")
  if emptyNode.isSome and cfIgnoreEmptyPassword notin opts.setFlags:
    let n = emptyNode.get
    if n.args.len < 1:
      raise newException(ValueError, "ignore-empty-password requires a boolean value")
    opts.ignoreEmptyPassword = n.args[0].kBool()

proc applyConfigFile*(opts: var Options; path: string) =
  ## Reads and applies a KDL config file. Raises ``ValueError`` with the
  ## file path included on parse/validation failures.
  var doc: KdlDoc
  try:
    doc = parseKdlFile(path)
  except CatchableError as e:
    raise newException(ValueError,
      "failed to parse config '" & path & "': " & e.msg)
  try:
    opts.applyConfigDoc(doc)
  except ValueError as e:
    raise newException(ValueError,
      "invalid config '" & path & "': " & e.msg)

proc loadConfig*(opts: var Options) =
  ## Loads configuration following the documented precedence:
  ## ``--no-config`` short-circuits; an explicit ``--config`` path is
  ## required to exist; otherwise the XDG search path is consulted.
  if opts.noConfig:
    return
  if opts.configPath.isSome:
    let path = opts.configPath.get
    if not fileExists(path):
      raise newException(ValueError, "config file not found: " & path)
    opts.applyConfigFile(path)
    return
  let discovered = findConfigFile()
  if discovered.isSome:
    opts.applyConfigFile(discovered.get)
