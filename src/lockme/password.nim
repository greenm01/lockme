type
  PasswordBuffer* = object
    bytes*: string
    limit*: int

proc initPasswordBuffer*(limit = 1024): PasswordBuffer =
  PasswordBuffer(bytes: "", limit: limit)

proc clear*(p: var PasswordBuffer) =
  if p.bytes.len > 0:
    zeroMem(addr p.bytes[0], p.bytes.len)
  p.bytes.setLen(0)

proc appendUtf8*(p: var PasswordBuffer; s: string): bool =
  if s.len == 0:
    return true
  if p.bytes.len + s.len > p.limit:
    return false
  p.bytes.add(s)
  true

proc popCodepoint*(p: var PasswordBuffer) =
  if p.bytes.len == 0:
    return

  var i = p.bytes.len - 1
  while i > 0 and (ord(p.bytes[i]) and 0b1100_0000) == 0b1000_0000:
    dec i
  p.bytes.setLen(i)

proc len*(p: PasswordBuffer): int =
  p.bytes.len
