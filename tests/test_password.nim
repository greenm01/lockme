import std/unittest

import lockme/password

proc s(b: seq[byte]): string =
  result = newString(b.len)
  if b.len > 0:
    copyMem(addr result[0], unsafeAddr b[0], b.len)

suite "PasswordBuffer":
  test "append and clear":
    var p = initPasswordBuffer()
    check p.appendString("abc")
    check p.len == 3
    check s(p.bytesView) == "abc"
    p.clear()
    check p.len == 0
    p.destroy()

  test "rejects oversized append":
    var p = initPasswordBuffer()
    var big = newString(SizeMax + 1)
    for i in 0 ..< big.len:
      big[i] = 'a'
    check not p.appendString(big)
    check p.len == 0
    p.destroy()

  test "fills exactly to capacity":
    var p = initPasswordBuffer()
    var maxStr = newString(SizeMax)
    for i in 0 ..< maxStr.len:
      maxStr[i] = 'x'
    check p.appendString(maxStr)
    check p.len == SizeMax
    check not p.appendString("y")
    p.destroy()

  test "pop UTF-8 codepoint":
    var p = initPasswordBuffer()
    check p.appendString("a" & "é" & "中")
    p.popCodepoint()
    check s(p.bytesView) == "aé"
    p.popCodepoint()
    check s(p.bytesView) == "a"
    p.popCodepoint()
    check p.len == 0
    p.destroy()

  test "clear zeroes underlying memory":
    var p = initPasswordBuffer()
    check p.appendString("secret")
    let raw = cast[ptr UncheckedArray[byte]](p.rawPtr)
    check raw[0] == byte('s')
    p.clear()
    # After clear, the underlying bytes must be zero.
    check raw[0] == 0
    check raw[5] == 0
    p.destroy()

  test "popCodepoint zeroes popped bytes":
    var p = initPasswordBuffer()
    check p.appendString("ab")
    let raw = cast[ptr UncheckedArray[byte]](p.rawPtr)
    check raw[1] == byte('b')
    p.popCodepoint()
    check raw[1] == 0
    check p.len == 1
    p.destroy()
