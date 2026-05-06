import ./matrix
import ./font8x16

type
  MatrixRenderGeometry* = object
    width*, height*: int
    cols*, rows*: int
    scale*: int

  MatrixShmBufferLayout* = object
    valid*: bool
    stride*: int
    size*: int

  MatrixRenderer* = ref object
    scale*: int

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

proc initMatrixRenderer*(bitmapScale: int): MatrixRenderer =
  MatrixRenderer(scale: max(bitmapScale, 1))

proc close*(renderer: MatrixRenderer) =
  discard

proc matrixRenderGeometry*(surfaceWidth, surfaceHeight: int, renderer: MatrixRenderer): MatrixRenderGeometry =
  let scale = if renderer.isNil: 1 else: renderer.scale
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

proc buildMatrixGlyphAtlas*(renderer: MatrixRenderer): MatrixGlyphAtlas =
  result.glyphCount = MatrixGlyphs.len
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

proc renderMatrix*(rain: MatrixRain, renderer: MatrixRenderer, data: ptr UncheckedArray[uint32], width, height: int) =
  let scale = if renderer.isNil: 1 else: renderer.scale
  renderMatrix(rain, data, width, height, scale)
