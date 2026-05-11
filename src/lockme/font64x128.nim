import std/math

import ./font8x16

const
  HighResGlyphWidth* = 64
  HighResGlyphHeight* = 128
  HighResGlyphScaleX = HighResGlyphWidth div 8
  HighResGlyphScaleY = HighResGlyphHeight div 16
  DistanceSoftness = 0.75

type
  Glyph64x128* = array[HighResGlyphWidth * HighResGlyphHeight, uint8]
  Font64x128* = array[Font8x16.len, Glyph64x128]

proc glyphBit(glyph: Glyph8x16; x, y: int): bool {.inline.} =
  x >= 0 and x < 8 and y >= 0 and y < 16 and
    (glyph[y] and (0x80'u8 shr x)) != 0

proc rectDistance(px, py: float; x, y: int): float =
  let left = float(x)
  let top = float(y)
  let right = left + 1.0
  let bottom = top + 1.0

  if px >= left and px <= right and py >= top and py <= bottom:
    return min(min(px - left, right - px), min(py - top, bottom - py))

  let dx =
    if px < left: left - px
    elif px > right: px - right
    else: 0.0
  let dy =
    if py < top: top - py
    elif py > bottom: py - bottom
    else: 0.0
  sqrt(dx * dx + dy * dy)

proc sampleGlyphDistance(glyph: Glyph8x16; srcX, srcY: float): float =
  let inside = glyph.glyphBit(int(floor(srcX)), int(floor(srcY)))
  var nearest = Inf

  for y in -1 .. 16:
    for x in -1 .. 8:
      if glyph.glyphBit(x, y) != inside:
        nearest = min(nearest, rectDistance(srcX, srcY, x, y))

  if inside: nearest else: -nearest

proc alphaFromDistance(distance: float): uint8 =
  let coverage = clamp(0.5 + distance / DistanceSoftness, 0.0, 1.0)
  uint8(int(coverage * 255.0 + 0.5))

proc buildGlyph64x128*(glyph: Glyph8x16): Glyph64x128 =
  for row in 0 ..< HighResGlyphHeight:
    let srcY = (float(row) + 0.5) / float(HighResGlyphScaleY)
    for col in 0 ..< HighResGlyphWidth:
      let srcX = (float(col) + 0.5) / float(HighResGlyphScaleX)
      result[row * HighResGlyphWidth + col] =
        alphaFromDistance(sampleGlyphDistance(glyph, srcX, srcY))

proc buildFont64x128*(): Font64x128 =
  for glyphIdx in 0 ..< Font8x16.len:
    result[glyphIdx] = buildGlyph64x128(Font8x16[glyphIdx])

let KoineFont64x128* = buildFont64x128()
