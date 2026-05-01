import std/os

import lockme/cli
import lockme/config
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
    if opts.checkProtocols:
      checkProtocols(opts)
    else:
      runLock(opts)
  except ValueError as e:
    stderr.writeLine("lockme: " & e.msg)
    quit(1)
  except OSError as e:
    stderr.writeLine("lockme: " & e.msg)
    quit(1)
