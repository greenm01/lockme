import std/unittest

import lockme/[font8x16, matrix, matrix_render]

suite "matrix":
  test "bitmap fallback glyph table matches matrix glyph set":
    check Font8x16.len == MatrixGlyphs.len

  test "zero-height rain is safe":
    var rain = initMatrixRain(2, 0)
    rain.advance()
    check rain.columns.len == 2
    for column in rain.columns:
      check column.glyphs.len == 0

  test "render clears to black for empty rain":
    var rain = initMatrixRain(0, 0)
    var pixels = newSeq[uint32](8)
    for i in 0 ..< pixels.len:
      pixels[i] = 0xffffffff'u32
    renderMatrix(rain, cast[ptr UncheckedArray[uint32]](addr pixels[0]), 2, 4)
    for pixel in pixels:
      check pixel == 0xff000000'u32

  test "render draws visible glyph pixels":
    var rain = initMatrixRain(1, 3)
    rain.columns[0].headRow = 1
    rain.columns[0].tailRow = 0
    rain.columns[0].glyphs = @[0, MatrixGlyphs.high, 0]

    var pixels = newSeq[uint32](8 * 48)
    renderMatrix(rain, cast[ptr UncheckedArray[uint32]](addr pixels[0]), 8, 48)

    var visible = false
    for pixel in pixels:
      if pixel != 0xff000000'u32:
        visible = true
    check visible

  test "render geometry uses native cell-aligned size":
    let geometry = matrixRenderGeometry(3840, 2160)
    check geometry.width == 3840
    check geometry.height == 2160
    check geometry.cols == 480
    check geometry.rows == 135

  test "render geometry keeps small surfaces on cell boundaries":
    let geometry = matrixRenderGeometry(799, 599)
    check geometry.width == 792
    check geometry.height == 592
    check geometry.cols == 99
    check geometry.rows == 37

  test "render geometry supports scaled cells":
    let geometry = matrixRenderGeometry(799, 599, 2)
    check geometry.width == 784
    check geometry.height == 576
    check geometry.cols == 49
    check geometry.rows == 18
    check geometry.scale == 2

  test "scaled render draws larger glyph pixels":
    var rain = initMatrixRain(1, 1)
    rain.columns[0].headRow = 0
    rain.columns[0].tailRow = 0
    rain.columns[0].glyphs = @[MatrixGlyphs.high]

    var normal = newSeq[uint32](8 * 16)
    var scaled = newSeq[uint32](16 * 32)
    renderMatrix(rain, cast[ptr UncheckedArray[uint32]](addr normal[0]), 8, 16)
    renderMatrix(rain, cast[ptr UncheckedArray[uint32]](addr scaled[0]), 16, 32, 2)

    var normalLit = 0
    var scaledLit = 0
    for pixel in normal:
      if pixel != 0xff000000'u32:
        inc normalLit
    for pixel in scaled:
      if pixel != 0xff000000'u32:
        inc scaledLit
    check scaledLit == normalLit * 4

  test "initialized rain renders visible pixels":
    var rain = initMatrixRain(10, 10)
    var pixels = newSeq[uint32](80 * 160)
    renderMatrix(rain, cast[ptr UncheckedArray[uint32]](addr pixels[0]), 80, 160)

    var visible = false
    for pixel in pixels:
      if pixel != 0xff000000'u32:
        visible = true
    check visible

  test "font renderer initializes from fontconfig":
    let renderer = initMatrixRenderer("monospace", "", 18, 24, 2)
    check renderer.usesFontRenderer()
    check renderer.font.cellWidth > 0
    check renderer.font.cellHeight >= 24

  test "font renderer geometry uses font metrics":
    let renderer = initMatrixRenderer("monospace", "", 18, 24, 2)
    check renderer.usesFontRenderer()
    let geometry = matrixRenderGeometry(799, 599, renderer)
    check geometry.width == geometry.cols * renderer.font.cellWidth
    check geometry.height == geometry.rows * renderer.font.cellHeight
    check geometry.width <= 799
    check geometry.height <= 599

  test "font renderer produces antialiased pixels":
    let renderer = initMatrixRenderer("monospace", "", 18, 24, 2)
    check renderer.usesFontRenderer()

    var rain = initMatrixRain(1, 1)
    rain.columns[0].headRow = 0
    rain.columns[0].tailRow = 0
    rain.columns[0].glyphs = @[MatrixGlyphs.high]

    let width = renderer.font.cellWidth
    let height = renderer.font.cellHeight
    var pixels = newSeq[uint32](width * height)
    renderMatrix(rain, renderer, cast[ptr UncheckedArray[uint32]](addr pixels[0]), width, height)

    var intermediate = false
    for pixel in pixels:
      if pixel != 0xff000000'u32 and pixel != 0xff80ff80'u32:
        intermediate = true
    check intermediate

  test "matrix ticker ignores early input wakeups":
    var ticker: MatrixTicker
    check matrixFrameTimeoutMs(ticker, true, 1000, 80) == 0
    check matrixFrameDue(ticker, true, 1000, 80)
    check ticker.nextAtMs == 1080

    check matrixFrameTimeoutMs(ticker, true, 1020, 80) == 60
    check not matrixFrameDue(ticker, true, 1020, 80)
    check ticker.nextAtMs == 1080

    check matrixFrameTimeoutMs(ticker, true, 1080, 80) == 0
    check matrixFrameDue(ticker, true, 1080, 80)
    check ticker.nextAtMs == 1160

  test "matrix ticker suspends while hidden without catch-up":
    var ticker: MatrixTicker
    check matrixFrameDue(ticker, true, 1000, 80)
    check ticker.armed

    check not matrixFrameDue(ticker, false, 2000, 80)
    check not ticker.armed

    check matrixFrameTimeoutMs(ticker, true, 3000, 80) == 0
    check matrixFrameDue(ticker, true, 3000, 80)
    check ticker.nextAtMs == 3080
