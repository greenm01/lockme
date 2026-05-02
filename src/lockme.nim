import std/os

import lockme/cli
import lockme/config
import lockme/preview
import lockme/wayland

when isMainModule:
  try:
    var opts = parseOptions(commandLineParams())
    if opts.showHelp:
      stdout.write(Usage)
      quit(0)
    if opts.showVersion:
      echo Version
      quit(0)
    opts.loadConfig()
    if opts.devWindow:
      if not opts.devMode:
        raise newException(ValueError, "--dev-window requires --dev-mode")
      runDevWindow(opts)
    elif opts.checkProtocols:
      checkProtocols(opts)
    else:
      runLock(opts)
  except ValueError as e:
    stderr.writeLine("lockme: " & e.msg)
    quit(1)
  except OSError as e:
    stderr.writeLine("lockme: " & e.msg)
    quit(1)
