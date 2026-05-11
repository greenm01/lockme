import std/unittest

import lockme/[font64x128, matrix, matrix_render]

proc glyphCell(atlas: MatrixGlyphAtlas; glyphIdx: int): seq[uint8] =
  result = newSeq[uint8](atlas.cellWidth * atlas.cellHeight)
  let cellX = glyphIdx * atlas.cellWidth
  for y in 0 ..< atlas.cellHeight:
    for x in 0 ..< atlas.cellWidth:
      result[y * atlas.cellWidth + x] = atlas.pixels[y * atlas.width + cellX + x]

proc distinctGlyphCellCount(atlas: MatrixGlyphAtlas): int =
  var cells: seq[seq[uint8]]
  for glyphIdx in 0 ..< atlas.glyphCount:
    let cell = atlas.glyphCell(glyphIdx)
    var seen = false
    for existing in cells:
      if existing == cell:
        seen = true
        break
    if not seen:
      cells.add cell
  cells.len

proc visibleGlyphCount(rain: MatrixRain): int =
  for column in rain.columns:
    if column.headRow < 0:
      continue
    let visibleTop = max(0, column.tailRow)
    let visibleBottom = min(rain.height - 1, column.headRow)
    if visibleTop > visibleBottom:
      continue
    result += visibleBottom - visibleTop + 1

proc distinctVisibleGlyphCount(rain: MatrixRain): int =
  var seen = newSeq[bool](MatrixGlyphs.len)
  for column in rain.columns:
    if column.headRow < 0:
      continue
    let visibleTop = max(0, column.tailRow)
    let visibleBottom = min(rain.height - 1, column.headRow)
    if visibleTop > visibleBottom:
      continue
    for row in visibleTop .. visibleBottom:
      let glyph = column.glyphs[row]
      if glyph >= 0 and glyph < seen.len and not seen[glyph]:
        seen[glyph] = true
        inc result

suite "matrix":
  test "glyph sources match matrix glyph set":
    check KoineGlyphCount == MatrixGlyphs.len
    check KoineFont64x128.len == MatrixGlyphs.len
    check HighResGlyphWidth == 64
    check HighResGlyphHeight == 128
    check KoineFont64x128[0].len == HighResGlyphWidth * HighResGlyphHeight

  test "high-resolution glyph source contains visible coverage alpha":
    var intermediate = false
    var strong = false
    for glyph in KoineFont64x128:
      var visible = false
      for pixel in glyph:
        if pixel > 0'u8:
          visible = true
        if pixel > 0'u8 and pixel < 255'u8:
          intermediate = true
        if pixel > 200'u8:
          strong = true
      check visible
    check intermediate
    check strong

  test "glyph atlas uses matrix glyph set":
    let renderer = initMatrixRenderer(2.0)
    let atlas = buildMatrixGlyphAtlas(renderer)
    check atlas.glyphCount == MatrixGlyphs.len
    check atlas.width == atlas.cellWidth * MatrixGlyphs.len
    check atlas.height == atlas.cellHeight
    check atlas.pixels.len == atlas.width * atlas.height

  test "glyph atlas contains distinct glyph cells":
    let renderer = initMatrixRenderer(2.0)
    let atlas = buildMatrixGlyphAtlas(renderer)
    check atlas.distinctGlyphCellCount() > 1

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
    let geometry = matrixRenderGeometry(799, 599, 2.0)
    check geometry.width == 784
    check geometry.height == 576
    check geometry.cols == 49
    check geometry.rows == 18
    check geometry.scale == 2.0

  test "render geometry supports fractional scaled cells":
    let geometry = matrixRenderGeometry(799, 599, 1.5)
    check geometry.width == 792
    check geometry.height == 576
    check geometry.cols == 66
    check geometry.rows == 24
    check geometry.scale == 1.5

  test "renderer geometry uses glyph scale":
    let renderer = initMatrixRenderer(3.0)
    let geometry = matrixRenderGeometry(799, 599, renderer)
    check geometry.width == 792
    check geometry.height == 576
    check geometry.cols == 33
    check geometry.rows == 12
    check geometry.scale == 3.0

  test "fractional glyph atlas contains intermediate alpha":
    let renderer = initMatrixRenderer(1.5)
    let atlas = buildMatrixGlyphAtlas(renderer)
    check atlas.cellWidth == 12
    check atlas.cellHeight == 24
    var intermediate = false
    for pixel in atlas.pixels:
      if pixel > 0'u8 and pixel < 255'u8:
        intermediate = true
        break
    check intermediate

  test "scaled render draws a larger antialiased glyph":
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
    check scaledLit > normalLit

  test "initialized rain renders visible pixels":
    var rain = initMatrixRain(10, 10)
    var pixels = newSeq[uint32](80 * 160)
    renderMatrix(rain, cast[ptr UncheckedArray[uint32]](addr pixels[0]), 80, 160)

    var visible = false
    for pixel in pixels:
      if pixel != 0xff000000'u32:
        visible = true
    check visible

  test "initialized rain uses more than one visible glyph":
    var rain = initMatrixRain(40, 20)
    for _ in 0 ..< 20:
      rain.advance()
    check rain.visibleGlyphCount() > 1
    check rain.distinctVisibleGlyphCount() > 1

  test "column reset reuses glyph storage":
    var rain = initMatrixRain(1, 4)
    let original = cast[uint](addr rain.columns[0].glyphs[0])

    rain.columns[0].gapRemaining = 0
    rain.columns[0].length = 3
    rain.columns[0].updateEvery = 1
    rain.columns[0].phase = 0
    rain.columns[0].headRow = 4
    rain.columns[0].tailRow = 4
    rain.advance()

    check rain.columns[0].glyphs.len == 4
    check cast[uint](addr rain.columns[0].glyphs[0]) == original

  test "matrix shm layout validates stride and size":
    let layout = matrixShmBufferLayout(3840, 2160)
    check layout.valid
    check layout.stride == 3840 * 4
    check layout.size == 3840 * 2160 * 4

  test "matrix shm layout rejects invalid dimensions":
    check not matrixShmBufferLayout(0, 2160).valid
    check not matrixShmBufferLayout(3840, 0).valid
    check not matrixShmBufferLayout(-1, 2160).valid
    check not matrixShmBufferLayout(3840, -1).valid

  test "matrix shm layout caps malicious dimensions":
    check matrixShmBufferLayout(MatrixShmMaxDimension, MatrixShmMaxDimension).valid
    check not matrixShmBufferLayout(MatrixShmMaxDimension + 1, 1).valid
    check not matrixShmBufferLayout(1, MatrixShmMaxDimension + 1).valid
    check not matrixShmBufferLayout((high(int32) div 4) + 1, 1).valid

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
