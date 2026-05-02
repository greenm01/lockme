import ./matrix
import ./font8x16
import ./matrix_font

type
  MatrixRenderGeometry* = object
    width*, height*: int
    cols*, rows*: int
    scale*: int

  MatrixShmBufferLayout* = object
    valid*: bool
    stride*: int
    size*: int

  MatrixRenderKind* = enum
    mrBitmap, mrFont

  MatrixRenderer* = ref object
    kind*: MatrixRenderKind
    scale*: int
    font*: MatrixFont

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

proc matrixRenderGeometry*(surfaceWidth, surfaceHeight: int, scale = 1): MatrixRenderGeometry =
  let cellScale = max(scale, 1)
  let cellWidth = GlyphWidth * cellScale
  let cellHeight = GlyphHeight * cellScale
  result.scale = cellScale
  result.cols = max(surfaceWidth, 0) div cellWidth
  result.rows = max(surfaceHeight, 0) div cellHeight
  result.width = result.cols * cellWidth
  result.height = result.rows * cellHeight

proc initMatrixRenderer*(fontFamily, fontPath: string; fontSize, lineHeight, bitmapScale: int): MatrixRenderer =
  let font = loadMatrixFont(fontFamily, fontPath, fontSize, lineHeight)
  if font.isNil:
    return MatrixRenderer(kind: mrBitmap, scale: max(bitmapScale, 1))
  MatrixRenderer(kind: mrFont, scale: max(bitmapScale, 1), font: font)

proc usesFontRenderer*(renderer: MatrixRenderer): bool =
  not renderer.isNil and renderer.kind == mrFont and not renderer.font.isNil

proc close*(renderer: MatrixRenderer) =
  if renderer.usesFontRenderer():
    renderer.font.close()

proc matrixRenderGeometry*(surfaceWidth, surfaceHeight: int, renderer: MatrixRenderer): MatrixRenderGeometry =
  if renderer.usesFontRenderer():
    let cellWidth = renderer.font.cellWidth
    let cellHeight = renderer.font.cellHeight
    result.scale = 1
    result.cols = max(surfaceWidth, 0) div cellWidth
    result.rows = max(surfaceHeight, 0) div cellHeight
    result.width = result.cols * cellWidth
    result.height = result.rows * cellHeight
  else:
    let scale = if renderer.isNil: 1 else: renderer.scale
    result = matrixRenderGeometry(surfaceWidth, surfaceHeight, scale)

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

proc drawBitmapGlyphAlpha(atlas: var MatrixGlyphAtlas; glyphIdx, cellX: int; scale = 1) =
  if glyphIdx < 0 or glyphIdx >= Font8x16.len: return
  let cellScale = max(scale, 1)
  let glyph = Font8x16[glyphIdx]
  for row in 0 ..< GlyphHeight:
    let bits = glyph[row]
    for col in 0 ..< GlyphWidth:
      if (bits and (0x80'u8 shr col)) == 0:
        continue
      let px = cellX + col * cellScale
      let py = row * cellScale
      for sy in 0 ..< cellScale:
        let ty = py + sy
        if ty < 0 or ty >= atlas.height: continue
        for sx in 0 ..< cellScale:
          let tx = px + sx
          if tx < cellX or tx >= cellX + atlas.cellWidth: continue
          atlas.pixels[ty * atlas.width + tx] = 255'u8

proc drawFontGlyphAlpha(atlas: var MatrixGlyphAtlas; cellX: int; baseline: int; glyph: MatrixGlyphBitmap) =
  let advancePad = max(0, (atlas.cellWidth - glyph.advance) div 2)
  let originX = cellX + advancePad + glyph.left
  let originY = baseline - glyph.top
  let cellRight = cellX + atlas.cellWidth
  for row in 0 ..< glyph.height:
    let ty = originY + row
    if ty < 0 or ty >= atlas.cellHeight:
      continue
    for col in 0 ..< glyph.width:
      let tx = originX + col
      if tx < cellX or tx >= cellRight:
        continue
      let alpha = glyph.pixels[row * glyph.width + col]
      if alpha != 0:
        atlas.pixels[ty * atlas.width + tx] = alpha

proc buildMatrixGlyphAtlas*(renderer: MatrixRenderer): MatrixGlyphAtlas =
  result.glyphCount = MatrixGlyphs.len
  if renderer.usesFontRenderer():
    result.cellWidth = renderer.font.cellWidth
    result.cellHeight = renderer.font.cellHeight
    result.width = result.cellWidth * result.glyphCount
    result.height = result.cellHeight
    result.pixels = newSeq[uint8](result.width * result.height)
    for glyphIdx, glyph in renderer.font.glyphs:
      result.drawFontGlyphAlpha(glyphIdx * result.cellWidth, renderer.font.baseline, glyph)
  else:
    let scale = if renderer.isNil: 1 else: renderer.scale
    result.cellWidth = GlyphWidth * max(scale, 1)
    result.cellHeight = GlyphHeight * max(scale, 1)
    result.width = result.cellWidth * result.glyphCount
    result.height = result.cellHeight
    result.pixels = newSeq[uint8](result.width * result.height)
    for glyphIdx in 0 ..< result.glyphCount:
      result.drawBitmapGlyphAlpha(glyphIdx, glyphIdx * result.cellWidth, scale)

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

proc div255Floor(x: uint32): uint32 {.inline.} =
  # Exact floor(x / 255) for x in 0..255*255 without hardware division.
  ((x + 1'u32) * 257'u32) shr 16

proc scaledColor(color: uint32; alpha: uint8): uint32 {.inline.} =
  let a = uint32(alpha)
  let r = div255Floor(((color shr 16) and 0xff'u32) * a)
  let g = div255Floor(((color shr 8) and 0xff'u32) * a)
  let b = div255Floor((color and 0xff'u32) * a)
  0xff000000'u32 or (r shl 16) or (g shl 8) or b

proc drawFontGlyph(data: ptr UncheckedArray[uint32], width, height: int, cellX, cellY: int, cellWidth, cellHeight, baseline: int, glyph: MatrixGlyphBitmap, color: uint32) =
  let advancePad = max(0, (cellWidth - glyph.advance) div 2)
  let originX = cellX + advancePad + glyph.left
  let originY = cellY + baseline - glyph.top
  let cellRight = cellX + cellWidth
  let cellBottom = cellY + cellHeight
  let rowStart = max(0, max(cellY - originY, -originY))
  let rowEnd = min(glyph.height, min(cellBottom - originY, height - originY))
  let colStart = max(0, max(cellX - originX, -originX))
  let colEnd = min(glyph.width, min(cellRight - originX, width - originX))
  if rowStart >= rowEnd or colStart >= colEnd:
    return

  for row in rowStart ..< rowEnd:
    let ty = originY + row
    let srcBase = row * glyph.width
    let dstBase = ty * width
    for col in colStart ..< colEnd:
      let tx = originX + col
      let alpha = glyph.pixels[srcBase + col]
      if alpha != 0:
        data[dstBase + tx] = scaledColor(color, alpha)

proc renderMatrixFont*(rain: MatrixRain, renderer: MatrixRenderer, data: ptr UncheckedArray[uint32], width, height: int) =
  for i in 0 ..< width * height:
    data[i] = 0xff000000'u32
  if not renderer.usesFontRenderer():
    return

  let font = renderer.font
  let trailColor = 0xff00aa00'u32
  let headColor = 0xff80ff80'u32

  for xIdx, column in rain.columns:
    let x = xIdx * font.cellWidth
    if x >= width: break
    if column.headRow < 0: continue

    let visibleTop = max(0, column.tailRow)
    let visibleBottom = min(rain.height - 1, column.headRow)

    for yIdx in visibleTop .. visibleBottom:
      let y = yIdx * font.cellHeight
      if y >= height: break
      let glyphIdx = column.glyphs[yIdx]
      if glyphIdx < 0 or glyphIdx >= font.glyphs.len:
        continue
      let color = if yIdx == column.headRow: headColor else: trailColor
      drawFontGlyph(data, width, height, x, y, font.cellWidth, font.cellHeight, font.baseline, font.glyphs[glyphIdx], color)

proc renderMatrix*(rain: MatrixRain, renderer: MatrixRenderer, data: ptr UncheckedArray[uint32], width, height: int) =
  if renderer.usesFontRenderer():
    renderMatrixFont(rain, renderer, data, width, height)
  else:
    let scale = if renderer.isNil: 1 else: renderer.scale
    renderMatrix(rain, data, width, height, scale)
