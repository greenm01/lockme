const MatrixFontPkgConfigDeps = "freetype2 fontconfig"
const MatrixFontPkgConfigCheck = gorgeEx("pkg-config --exists " & MatrixFontPkgConfigDeps)

when MatrixFontPkgConfigCheck.exitCode != 0:
  {.error: "missing system dependencies: install pkg-config plus development packages for freetype2 and fontconfig".}

{.passC: "-Isrc -Isrc/lockme " & gorge("pkg-config --cflags " & MatrixFontPkgConfigDeps).}
{.compile: "matrix_font_shim.c".}
{.passL: gorge("pkg-config --libs " & MatrixFontPkgConfigDeps).}

import ./matrix

type
  MatrixFontHandle {.importc: "struct lockme_matrix_font", header: "lockme/matrix_font_shim.h", incompleteStruct.} = object

  MatrixFontGlyphC {.importc: "struct lockme_matrix_glyph", header: "lockme/matrix_font_shim.h", bycopy.} = object
    width*, height*, left*, top*, advance*: int32
    pixels*: ptr UncheckedArray[uint8]

  MatrixGlyphBitmap* = object
    width*, height*, left*, top*, advance*: int
    pixels*: seq[uint8]

  MatrixFont* = ref object
    handle: ptr MatrixFontHandle
    cellWidth*, cellHeight*, baseline*: int
    glyphs*: seq[MatrixGlyphBitmap]

proc matrixFontOpen(family, path: cstring; pixelSize: int32): ptr MatrixFontHandle
  {.importc: "lockme_matrix_font_open", header: "lockme/matrix_font_shim.h".}
proc matrixFontClose(font: ptr MatrixFontHandle)
  {.importc: "lockme_matrix_font_close", header: "lockme/matrix_font_shim.h".}
proc matrixFontMetrics(font: ptr MatrixFontHandle; cellWidth, lineHeight, baseline: ptr int32): int32
  {.importc: "lockme_matrix_font_metrics", header: "lockme/matrix_font_shim.h".}
proc matrixFontRasterize(font: ptr MatrixFontHandle; utf8: cstring; glyph: ptr MatrixFontGlyphC): int32
  {.importc: "lockme_matrix_font_rasterize", header: "lockme/matrix_font_shim.h".}
proc matrixGlyphFree(glyph: ptr MatrixFontGlyphC)
  {.importc: "lockme_matrix_glyph_free", header: "lockme/matrix_font_shim.h".}

proc close*(font: MatrixFont) =
  if not font.isNil and not font.handle.isNil:
    matrixFontClose(font.handle)
    font.handle = nil

proc loadMatrixFont*(family, path: string; fontSize, lineHeight: int): MatrixFont =
  let handle = matrixFontOpen(family.cstring, path.cstring, int32(fontSize))
  if handle.isNil:
    return nil

  var cCellWidth, cLineHeight, cBaseline: int32
  if matrixFontMetrics(handle, addr cCellWidth, addr cLineHeight, addr cBaseline) != 0:
    matrixFontClose(handle)
    return nil

  result = MatrixFont(
    handle: handle,
    cellWidth: max(1, int(cCellWidth)),
    cellHeight: max(max(1, lineHeight), int(cLineHeight)),
    baseline: max(1, int(cBaseline)),
    glyphs: newSeq[MatrixGlyphBitmap](MatrixGlyphs.len)
  )

  for i, raw in MatrixGlyphs:
    var glyph: MatrixFontGlyphC
    if matrixFontRasterize(handle, raw.cstring, addr glyph) != 0:
      matrixFontClose(handle)
      result.handle = nil
      return nil
    defer: matrixGlyphFree(addr glyph)
    let pixelCount = max(0, int(glyph.width) * int(glyph.height))
    var pixels = newSeq[uint8](pixelCount)
    for j in 0 ..< pixelCount:
      pixels[j] = glyph.pixels[j]
    result.glyphs[i] = MatrixGlyphBitmap(
      width: int(glyph.width),
      height: int(glyph.height),
      left: int(glyph.left),
      top: int(glyph.top),
      advance: max(1, int(glyph.advance)),
      pixels: pixels
    )
