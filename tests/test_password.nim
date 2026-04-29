import std/unittest

import lockme/password

suite "PasswordBuffer":
  test "append and clear":
    var p = initPasswordBuffer(8)
    check p.appendUtf8("abc")
    check p.len == 3
    p.clear()
    check p.len == 0

  test "limit":
    var p = initPasswordBuffer(3)
    check p.appendUtf8("abc")
    check not p.appendUtf8("d")
    check p.bytes == "abc"

  test "pop UTF-8 codepoint":
    var p = initPasswordBuffer()
    check p.appendUtf8("a" & "é" & "中")
    p.popCodepoint()
    check p.bytes == "aé"
    p.popCodepoint()
    check p.bytes == "a"
    p.popCodepoint()
    check p.bytes == ""
