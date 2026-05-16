## Hardened password buffer.
##
## Allocates a fixed-size, page-aligned buffer that is `mlock(2)`'d so it
## cannot be paged to swap and `madvise(MADV_DONTDUMP)`'d so it is excluded
## from core dumps. Clearing uses `explicit_bzero(3)` which the compiler is
## not permitted to elide.
##
## Linux-only by design (relies on `MADV_DONTDUMP`, `explicit_bzero`).

{.passC: "-D_GNU_SOURCE".}

import std/posix

const
  SizeMax* = 1024
  ScPageSize = 30.cint # Linux: _SC_PAGESIZE
  MadvDontdump = 16.cint # Linux: MADV_DONTDUMP

proc posix_memalign(
  memptr: ptr pointer, alignment, size: csize_t
): cint {.importc, header: "<stdlib.h>".}

proc c_free(p: pointer) {.importc: "free", header: "<stdlib.h>".}
proc c_mlock(
  p: pointer, len: csize_t
): cint {.importc: "mlock", header: "<sys/mman.h>".}

proc c_munlock(
  p: pointer, len: csize_t
): cint {.importc: "munlock", header: "<sys/mman.h>".}

proc c_madvise(
  p: pointer, len: csize_t, advice: cint
): cint {.importc: "madvise", header: "<sys/mman.h>".}

proc explicit_bzero(p: pointer, n: csize_t) {.importc, header: "<string.h>".}
proc sysconf(name: cint): clong {.importc, header: "<unistd.h>".}

type PasswordBuffer* = object
  data: ptr UncheckedArray[byte]
  cap: int
  length: int

proc pageSize(): int =
  let v = sysconf(ScPageSize)
  if v <= 0:
    return 4096
  int(v)

proc fail(msg: string) {.noreturn.} =
  quit("lockme: " & msg, 1)

proc initPasswordBuffer*(): PasswordBuffer =
  let page = pageSize()
  # Round capacity up to a multiple of page size so mlock/madvise cover
  # exactly the allocation we own.
  let cap = ((SizeMax + page - 1) div page) * page
  var raw: pointer = nil
  let rc = posix_memalign(addr raw, csize_t(page), csize_t(cap))
  if rc != 0 or raw.isNil:
    fail("failed to allocate password buffer")

  # mlock with retry on EAGAIN, matching waylock's behavior.
  block mlockBlock:
    var attempts = 0
    while true:
      if c_mlock(raw, csize_t(cap)) == 0:
        break mlockBlock
      if errno != EAGAIN or attempts >= 10:
        c_free(raw)
        fail("failed to mlock password buffer (RLIMIT_MEMLOCK?)")
      inc attempts

  # madvise(DONTDUMP): warn-but-continue on non-EAGAIN failure.
  block dontdumpBlock:
    var attempts = 0
    while true:
      if c_madvise(raw, csize_t(cap), MadvDontdump) == 0:
        break dontdumpBlock
      if errno != EAGAIN:
        # Non-fatal: kernel may not support DONTDUMP; mlock still applied.
        stderr.writeLine(
          "lockme: warning: madvise(MADV_DONTDUMP) failed; password may be included in core dumps"
        )
        break dontdumpBlock
      if attempts >= 10:
        stderr.writeLine(
          "lockme: warning: madvise(MADV_DONTDUMP) repeatedly returned EAGAIN"
        )
        break dontdumpBlock
      inc attempts

  result =
    PasswordBuffer(data: cast[ptr UncheckedArray[byte]](raw), cap: cap, length: 0)

proc protectAfterFork*(p: var PasswordBuffer) =
  ## Re-apply mlock after fork(2) and refresh MADV_DONTDUMP for the child.
  ## Linux does not inherit memory locks across fork.
  if p.data.isNil:
    return
  discard c_mlock(p.data, csize_t(p.cap))
  discard c_madvise(p.data, csize_t(p.cap), MadvDontdump)

proc clear*(p: var PasswordBuffer) =
  if p.data.isNil:
    return
  explicit_bzero(p.data, csize_t(p.cap))
  p.length = 0

proc destroy*(p: var PasswordBuffer) =
  if p.data.isNil:
    return
  explicit_bzero(p.data, csize_t(p.cap))
  discard c_munlock(p.data, csize_t(p.cap))
  c_free(p.data)
  p.data = nil
  p.cap = 0
  p.length = 0

proc len*(p: PasswordBuffer): int {.inline.} =
  p.length

proc capacity*(p: PasswordBuffer): int {.inline.} =
  ## Logical capacity for password content (SizeMax), not the underlying
  ## page-rounded allocation.
  SizeMax

proc rawPtr*(p: PasswordBuffer): pointer {.inline.} =
  cast[pointer](p.data)

proc bytesPtr*(p: PasswordBuffer): pointer {.inline.} =
  ## Pointer to the start of valid content. May be nil if buffer is empty.
  if p.length == 0:
    return nil
  cast[pointer](p.data)

proc appendUtf8*(p: var PasswordBuffer, s: openArray[byte]): bool =
  if s.len == 0:
    return true
  if p.data.isNil:
    return false
  if p.length + s.len > SizeMax:
    return false
  copyMem(addr p.data[p.length], unsafeAddr s[0], s.len)
  p.length += s.len
  true

proc appendString*(p: var PasswordBuffer, s: string): bool =
  ## Convenience wrapper for tests and string sources. Caller is responsible
  ## for clearing the source `s` if it contained sensitive material.
  if s.len == 0:
    return true
  if p.data.isNil:
    return false
  if p.length + s.len > SizeMax:
    return false
  copyMem(addr p.data[p.length], unsafeAddr s[0], s.len)
  p.length += s.len
  true

proc setLength*(p: var PasswordBuffer, n: int): bool =
  ## Used by the auth child to size the buffer before reading exactly `n`
  ## bytes from the parent pipe. Caller must overwrite the [0, n) range.
  if p.data.isNil or n < 0 or n > SizeMax:
    return false
  p.length = n
  true

proc popCodepoint*(p: var PasswordBuffer) =
  if p.data.isNil or p.length == 0:
    return
  var i = p.length - 1
  while i > 0 and (int(p.data[i]) and 0b1100_0000) == 0b1000_0000:
    dec i
  let popped = p.length - i
  if popped > 0:
    explicit_bzero(addr p.data[i], csize_t(popped))
  p.length = i

proc bytesView*(p: PasswordBuffer): seq[byte] =
  ## Returns a copy of the current contents as a seq for tests only.
  ## Do NOT use in production code paths.
  result.setLen(p.length)
  if p.length > 0:
    copyMem(addr result[0], cast[pointer](p.data), p.length)
