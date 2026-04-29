import std/posix

type
  AuthConnection* = object
    readFd*: cint
    writeFd*: cint

  PamHandle {.importc: "pam_handle_t", header: "<security/pam_appl.h>", incompleteStruct.} = object

  PamMessage {.importc: "struct pam_message", header: "<security/pam_appl.h>", bycopy.} = object
    msgStyle {.importc: "msg_style".}: cint
    msg*: cstring

  PamMessageConst {.importc: "const struct pam_message", header: "<security/pam_appl.h>", bycopy.} = object

  PamResponse {.importc: "struct pam_response", header: "<security/pam_appl.h>", bycopy.} = object
    resp*: cstring
    respRetcode {.importc: "resp_retcode".}: cint

  PamConv {.importc: "struct pam_conv", header: "<security/pam_appl.h>", bycopy.} = object
    conv*: proc(numMsg: cint; msg: ptr ptr PamMessageConst; resp: ptr ptr PamResponse; appdata: pointer): cint {.cdecl.}
    appdataPtr {.importc: "appdata_ptr".}: pointer

  Passwd {.importc: "struct passwd", header: "<pwd.h>", bycopy.} = object
    pwName {.importc: "pw_name".}: cstring

const
  PamSuccess = 0.cint
  PamAbort = 26.cint
  PamPromptEchoOff = 1.cint
  PamReinitializeCred = 0x0008.cint
  AuthReadyByte = uint8(ord('R'))
  AuthInitFailedByte = uint8(ord('E'))

proc pam_start(serviceName, user: cstring; pamConv: ptr PamConv; pamh: ptr ptr PamHandle): cint
  {.importc, header: "<security/pam_appl.h>".}
proc pam_authenticate(pamh: ptr PamHandle; flags: cint): cint
  {.importc, header: "<security/pam_appl.h>".}
proc pam_setcred(pamh: ptr PamHandle; flags: cint): cint
  {.importc, header: "<security/pam_appl.h>".}
proc pam_end(pamh: ptr PamHandle; status: cint): cint
  {.importc, header: "<security/pam_appl.h>".}
proc pam_strerror(pamh: ptr PamHandle; errnum: cint): cstring
  {.importc, header: "<security/pam_appl.h>".}

proc getpwuid(uid: Uid): ptr Passwd {.importc, header: "<pwd.h>".}
proc calloc(count, size: csize_t): pointer {.importc, header: "<stdlib.h>".}
proc strdup(s: cstring): cstring {.importc, header: "<string.h>".}

var childPassword = ""

proc readExact(fd: cint; p: pointer; len: int): bool =
  var offset = 0
  while offset < len:
    let rc = read(fd, cast[pointer](cast[uint](p) + uint(offset)), len - offset)
    if rc <= 0:
      return false
    offset += rc
  true

proc writeExact(fd: cint; p: pointer; len: int): bool =
  var offset = 0
  while offset < len:
    let rc = write(fd, cast[pointer](cast[uint](p) + uint(offset)), len - offset)
    if rc <= 0:
      return false
    offset += rc
  true

proc readU32(fd: cint; value: var uint32): bool =
  var raw: array[4, uint8]
  if not readExact(fd, addr raw[0], raw.len):
    return false
  value = uint32(raw[0]) or (uint32(raw[1]) shl 8) or
    (uint32(raw[2]) shl 16) or (uint32(raw[3]) shl 24)
  true

proc writeU32(fd: cint; value: uint32): bool =
  var raw = [
    uint8(value and 0xff'u32),
    uint8((value shr 8) and 0xff'u32),
    uint8((value shr 16) and 0xff'u32),
    uint8((value shr 24) and 0xff'u32)
  ]
  writeExact(fd, addr raw[0], raw.len)

proc converse(numMsg: cint; msg: ptr ptr PamMessageConst; resp: ptr ptr PamResponse; appdata: pointer): cint {.cdecl.} =
  let responses = cast[ptr UncheckedArray[PamResponse]](calloc(csize_t(numMsg), csize_t(sizeof(PamResponse))))
  if responses.isNil:
    return 5.cint
  resp[] = cast[ptr PamResponse](responses)

  let messages = cast[ptr UncheckedArray[ptr PamMessage]](msg)
  for i in 0 ..< int(numMsg):
    let message = messages[i]
    if not message.isNil and message.msgStyle == PamPromptEchoOff:
      responses[i].resp = strdup(childPassword.cstring)
      if responses[i].resp.isNil:
        return 5.cint
  PamSuccess

proc readPassword(conn: AuthConnection): bool =
  var length: uint32
  if not readU32(conn.readFd, length):
    return false
  if length > 1024'u32:
    return false
  childPassword.setLen(int(length))
  if length == 0:
    return true
  readExact(conn.readFd, addr childPassword[0], int(length))

proc writeAuthResult(conn: AuthConnection; ok: bool): bool =
  var b = if ok: uint8(1) else: uint8(0)
  writeExact(conn.writeFd, addr b, 1)

proc writeAuthStatus(conn: AuthConnection; status: uint8): bool =
  var b = status
  writeExact(conn.writeFd, addr b, 1)

proc authLoop(conn: AuthConnection) {.noreturn.} =
  var pamh: ptr PamHandle
  let pw = getpwuid(getuid())
  if pw.isNil:
    discard writeAuthStatus(conn, AuthInitFailedByte)
    quit("lockme: failed to get current user for PAM", 1)

  var conv = PamConv(conv: converse, appdataPtr: nil)
  var status = pam_start("lockme", pw.pwName, addr conv, addr pamh)
  if status != PamSuccess:
    discard writeAuthStatus(conn, AuthInitFailedByte)
    quit("lockme: pam_start failed: " & $pam_strerror(nil, status), 1)
  if not writeAuthStatus(conn, AuthReadyByte):
    discard pam_end(pamh, status)
    quit("lockme: failed to notify parent that PAM is ready", 1)

  while true:
    if not readPassword(conn):
      discard pam_end(pamh, status)
      quit("lockme: failed to read password from parent", 1)

    status = pam_authenticate(pamh, 0)
    childPassword.setLen(0)

    if status == PamSuccess:
      discard writeAuthResult(conn, true)
      let credStatus = pam_setcred(pamh, PamReinitializeCred)
      discard pam_end(pamh, credStatus)
      quit(0)
    else:
      discard writeAuthResult(conn, false)
      if status == PamAbort:
        discard pam_end(pamh, status)
        quit(1)

proc forkAuthChild*(): AuthConnection =
  var parentToChild: array[0..1, cint]
  var childToParent: array[0..1, cint]

  if pipe(parentToChild) != 0 or pipe(childToParent) != 0:
    raise newException(OSError, "failed to create auth pipes")

  let pid = fork()
  if pid < 0:
    raise newException(OSError, "failed to fork auth child")

  if pid == 0:
    discard close(parentToChild[1])
    discard close(childToParent[0])
    authLoop(AuthConnection(readFd: parentToChild[0], writeFd: childToParent[1]))
  else:
    discard close(parentToChild[0])
    discard close(childToParent[1])
    result = AuthConnection(readFd: childToParent[0], writeFd: parentToChild[1])
    var status: uint8
    if not readExact(result.readFd, addr status, 1):
      raise newException(OSError, "auth child exited before PAM was ready")
    if status == AuthInitFailedByte:
      raise newException(OSError, "auth child failed to initialize PAM")
    if status != AuthReadyByte:
      raise newException(OSError, "auth child sent unexpected startup status")

proc sendPassword*(conn: AuthConnection; password: string): bool =
  if password.len > 1024:
    return false
  if not writeU32(conn.writeFd, uint32(password.len)):
    return false
  if password.len == 0:
    return true
  writeExact(conn.writeFd, unsafeAddr password[0], password.len)

proc readAuthResult*(conn: AuthConnection; ok: var bool): bool =
  var b: uint8
  if not readExact(conn.readFd, addr b, 1):
    return false
  if b == 1'u8:
    ok = true
    true
  elif b == 0'u8:
    ok = false
    true
  else:
    false
