import std/math

import ./matrix
import ./font8x16

type
  MatrixRenderGeometry* = object
    width*, height*: int
    cols*, rows*: int
    scale*: float

  MatrixShmBufferLayout* = object
    valid*: bool
    stride*: int
    size*: int

  MatrixRenderer* = ref object
    scale*: float

  MatrixGlyphAtlas* = object
    cellWidth*, cellHeight*: int
    width*, height*: int
    glyphCount*: int
    pixels*: seq[uint8]

const
  GlyphWidth = 8
  GlyphHeight = 16
  MatrixShmMaxDimension* = 16384
  MatrixShmBytesPerPixel = 4

proc matrixShmBufferLayout*(width, height: int): MatrixShmBufferLayout =
  if width <= 0 or height <= 0:
    return
  if width > MatrixShmMaxDimension or height > MatrixShmMaxDimension:
    return

  let stride64 = int64(width) * int64(MatrixShmBytesPerPixel)
  let size64 = stride64 * int64(height)
  if stride64 > int64(high(int32)) or size64 > int64(high(int32)):
    return

  MatrixShmBufferLayout(valid: true, stride: int(stride64), size: int(size64))

proc scaledDimension(base: int; scale: float): int =
  max(1, int(float(base) * max(scale, 1.0) + 0.5))

proc matrixRenderGeometry*(surfaceWidth, surfaceHeight: int, scale = 1.0): MatrixRenderGeometry =
  let cellScale = max(scale, 1.0)
  let cellWidth = scaledDimension(GlyphWidth, cellScale)
  let cellHeight = scaledDimension(GlyphHeight, cellScale)
  result.scale = cellScale
  result.cols = max(surfaceWidth, 0) div cellWidth
  result.rows = max(surfaceHeight, 0) div cellHeight
  result.width = result.cols * cellWidth
  result.height = result.rows * cellHeight

proc initMatrixRenderer*(bitmapScale: float): MatrixRenderer =
  MatrixRenderer(scale: max(bitmapScale, 1.0))

proc close*(renderer: MatrixRenderer) =
  discard

proc matrixRenderGeometry*(surfaceWidth, surfaceHeight: int, renderer: MatrixRenderer): MatrixRenderGeometry =
  let scale = if renderer.isNil: 1.0 else: renderer.scale
  matrixRenderGeometry(surfaceWidth, surfaceHeight, scale)

proc drawGlyph*(data: ptr UncheckedArray[uint32], width, height: int, x, y: int, glyphIdx: int, color: uint32, scale = 1) =
  if glyphIdx < 0 or glyphIdx >= Font8x16.len: return
  let cellScale = max(scale, 1)
  let glyph = Font8x16[glyphIdx]
  for i in 0 ..< GlyphHeight:
    let row = glyph[i]
    for j in 0 ..< GlyphWidth:
      if (row and (0x80'u8 shr j)) != 0:
        let px = x + j * cellScale
        let py = y + i * cellScale
        for sy in 0 ..< cellScale:
          let ty = py + sy
          if ty < 0 or ty >= height: continue
          for sx in 0 ..< cellScale:
            let tx = px + sx
            if tx < 0 or tx >= width: continue
            data[ty * width + tx] = color

proc bitmapGlyphBit(glyph: Glyph8x16; x, y: int): float =
  if x < 0 or x >= GlyphWidth or y < 0 or y >= GlyphHeight:
    return 0.0
  if (glyph[y] and (0x80'u8 shr x)) != 0:
    1.0
  else:
    0.0

proc sampleBitmapGlyph(glyph: Glyph8x16; srcX, srcY: float): uint8 =
  let x = srcX - 0.5
  let y = srcY - 0.5
  let x0 = int(floor(x))
  let y0 = int(floor(y))
  let fx = x - float(x0)
  let fy = y - float(y0)
  let a00 = bitmapGlyphBit(glyph, x0, y0)
  let a10 = bitmapGlyphBit(glyph, x0 + 1, y0)
  let a01 = bitmapGlyphBit(glyph, x0, y0 + 1)
  let a11 = bitmapGlyphBit(glyph, x0 + 1, y0 + 1)
  let top = a00 * (1.0 - fx) + a10 * fx
  let bottom = a01 * (1.0 - fx) + a11 * fx
  uint8(int((top * (1.0 - fy) + bottom * fy) * 255.0 + 0.5))

proc div255Floor(x: uint32): uint32 {.inline.} =
  ((x + 1'u32) * 257'u32) shr 16

proc scaledColor(color: uint32; alpha: uint8): uint32 {.inline.} =
  let a = uint32(alpha)
  let r = div255Floor(((color shr 16) and 0xff'u32) * a)
  let g = div255Floor(((color shr 8) and 0xff'u32) * a)
  let b = div255Floor((color and 0xff'u32) * a)
  0xff000000'u32 or (r shl 16) or (g shl 8) or b

proc drawBitmapGlyphAlpha(atlas: var MatrixGlyphAtlas; glyphIdx, cellX: int) =
  if glyphIdx < 0 or glyphIdx >= Font8x16.len: return
  let glyph = Font8x16[glyphIdx]
  let scaleX = float(GlyphWidth) / float(atlas.cellWidth)
  let scaleY = float(GlyphHeight) / float(atlas.cellHeight)
  for row in 0 ..< atlas.cellHeight:
    let srcY = (float(row) + 0.5) * scaleY
    for col in 0 ..< atlas.cellWidth:
      let srcX = (float(col) + 0.5) * scaleX
      atlas.pixels[row * atlas.width + cellX + col] = sampleBitmapGlyph(glyph, srcX, srcY)

proc buildMatrixGlyphAtlas*(renderer: MatrixRenderer): MatrixGlyphAtlas =
  result.glyphCount = MatrixGlyphs.len
  let scale = if renderer.isNil: 1.0 else: renderer.scale
  result.cellWidth = scaledDimension(GlyphWidth, scale)
  result.cellHeight = scaledDimension(GlyphHeight, scale)
  result.width = result.cellWidth * result.glyphCount
  result.height = result.cellHeight
  result.pixels = newSeq[uint8](result.width * result.height)
  for glyphIdx in 0 ..< result.glyphCount:
    result.drawBitmapGlyphAlpha(glyphIdx, glyphIdx * result.cellWidth)

proc renderMatrix*(rain: MatrixRain, data: ptr UncheckedArray[uint32], width, height: int, scale = 1) =
  # Clear buffer to black
  # explicit_bzero or just loop. Since we are drawing characters, we can just clear.
  # For performance, maybe only clear what changed, but simple is better for now.
  for i in 0 ..< width * height:
    data[i] = 0xff000000'u32

  let cellScale = max(scale, 1)
  let cellWidth = GlyphWidth * cellScale
  let cellHeight = GlyphHeight * cellScale
  let trailColor = 0xff00aa00'u32 
  let headColor = 0xff80ff80'u32 

  for xIdx, column in rain.columns:
    let x = xIdx * cellWidth
    if x >= width: break
    if column.headRow < 0: continue
    
    let visibleTop = max(0, column.tailRow)
    let visibleBottom = min(rain.height - 1, column.headRow)
    
    for yIdx in visibleTop .. visibleBottom:
      let y = yIdx * cellHeight
      if y >= height: break
      let color = if yIdx == column.headRow: headColor else: trailColor
      drawGlyph(data, width, height, x, y, column.glyphs[yIdx], color, cellScale)

proc drawScaledGlyph(data: ptr UncheckedArray[uint32], width, height: int, x, y: int, glyphIdx: int, color: uint32, cellWidth, cellHeight: int) =
  if glyphIdx < 0 or glyphIdx >= Font8x16.len: return
  let glyph = Font8x16[glyphIdx]
  let scaleX = float(GlyphWidth) / float(cellWidth)
  let scaleY = float(GlyphHeight) / float(cellHeight)
  for row in 0 ..< cellHeight:
    let ty = y + row
    if ty < 0 or ty >= height: continue
    let srcY = (float(row) + 0.5) * scaleY
    for col in 0 ..< cellWidth:
      let tx = x + col
      if tx < 0 or tx >= width: continue
      let srcX = (float(col) + 0.5) * scaleX
      let alpha = sampleBitmapGlyph(glyph, srcX, srcY)
      if alpha != 0:
        data[ty * width + tx] = scaledColor(color, alpha)

proc renderMatrixScaled(rain: MatrixRain, data: ptr UncheckedArray[uint32], width, height: int, scale: float) =
  for i in 0 ..< width * height:
    data[i] = 0xff000000'u32

  let cellScale = max(scale, 1.0)
  let cellWidth = scaledDimension(GlyphWidth, cellScale)
  let cellHeight = scaledDimension(GlyphHeight, cellScale)
  let trailColor = 0xff00aa00'u32
  let headColor = 0xff80ff80'u32

  for xIdx, column in rain.columns:
    let x = xIdx * cellWidth
    if x >= width: break
    if column.headRow < 0: continue

    let visibleTop = max(0, column.tailRow)
    let visibleBottom = min(rain.height - 1, column.headRow)

    for yIdx in visibleTop .. visibleBottom:
      let y = yIdx * cellHeight
      if y >= height: break
      let color = if yIdx == column.headRow: headColor else: trailColor
      drawScaledGlyph(data, width, height, x, y, column.glyphs[yIdx], color, cellWidth, cellHeight)

proc renderMatrix*(rain: MatrixRain, renderer: MatrixRenderer, data: ptr UncheckedArray[uint32], width, height: int) =
  let scale = if renderer.isNil: 1.0 else: renderer.scale
  renderMatrixScaled(rain, data, width, height, scale)
