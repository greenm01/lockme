import ./matrix_render

const
  MatrixGpuPkgConfigDeps = "egl glesv2 wayland-egl"
  MatrixGpuPkgConfigCheck = gorgeEx("pkg-config --exists " & MatrixGpuPkgConfigDeps)

when MatrixGpuPkgConfigCheck.exitCode != 0:
  {.error: "missing system dependencies: install pkg-config plus development packages for egl, glesv2, and wayland-egl".}

{.passC: "-Isrc -Isrc/lockme " & gorge("pkg-config --cflags " & MatrixGpuPkgConfigDeps).}
{.compile: "matrix_gpu_shim.c".}
{.passL: gorge("pkg-config --libs " & MatrixGpuPkgConfigDeps).}

type
  MatrixGpuRenderer* = ref object
    handle: pointer
    width*, height*: int
    cellWidth*, cellHeight*: int

proc gpuCreate(
  display, surface: pointer;
  width, height, cellWidth, cellHeight, glyphCount: int32;
  atlasPixels: ptr UncheckedArray[uint8];
  atlasWidth, atlasHeight: int32): pointer
  {.importc: "lockme_matrix_gpu_create", header: "lockme/matrix_gpu_shim.h".}
proc gpuResize(handle: pointer; width, height: int32): int32
  {.importc: "lockme_matrix_gpu_resize", header: "lockme/matrix_gpu_shim.h".}
proc gpuRender(
  handle: pointer;
  timeSeconds: cdouble;
  fallSpeed, cycleSpeed, raindropLength, brightnessDecay: cfloat): int32
  {.importc: "lockme_matrix_gpu_render", header: "lockme/matrix_gpu_shim.h".}
proc gpuDestroy(handle: pointer)
  {.importc: "lockme_matrix_gpu_destroy", header: "lockme/matrix_gpu_shim.h".}
proc gpuLastError(): cstring
  {.importc: "lockme_matrix_gpu_last_error", header: "lockme/matrix_gpu_shim.h".}

proc matrixGpuLastError*(): string =
  $gpuLastError()

proc initMatrixGpuRenderer*(display, surface: pointer; width, height: int; atlas: MatrixGlyphAtlas): MatrixGpuRenderer =
  if atlas.pixels.len == 0 or atlas.width <= 0 or atlas.height <= 0 or atlas.glyphCount <= 0:
    return nil
  let pixels = cast[ptr UncheckedArray[uint8]](unsafeAddr atlas.pixels[0])
  let handle = gpuCreate(
    display,
    surface,
    width.int32,
    height.int32,
    atlas.cellWidth.int32,
    atlas.cellHeight.int32,
    atlas.glyphCount.int32,
    pixels,
    atlas.width.int32,
    atlas.height.int32
  )
  if handle.isNil:
    return nil
  MatrixGpuRenderer(
    handle: handle,
    width: width,
    height: height,
    cellWidth: atlas.cellWidth,
    cellHeight: atlas.cellHeight
  )

proc isNil*(renderer: MatrixGpuRenderer): bool =
  renderer == nil or renderer.handle.isNil

proc resize*(renderer: MatrixGpuRenderer; width, height: int): bool =
  if renderer.isNil:
    return false
  if renderer.width == width and renderer.height == height:
    return true
  if gpuResize(renderer.handle, width.int32, height.int32) == 0:
    return false
  renderer.width = width
  renderer.height = height
  true

proc render*(renderer: MatrixGpuRenderer; timeMs: int64; fallSpeed, cycleSpeed, raindropLength, brightnessDecay: float): bool =
  if renderer.isNil:
    return false
  gpuRender(
    renderer.handle,
    cdouble(timeMs.float / 1000.0),
    cfloat(fallSpeed),
    cfloat(cycleSpeed),
    cfloat(raindropLength),
    cfloat(brightnessDecay)
  ) != 0

proc close*(renderer: MatrixGpuRenderer) =
  if not renderer.isNil:
    gpuDestroy(renderer.handle)
    renderer.handle = nil
