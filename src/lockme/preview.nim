import std/[monotimes, posix, times]

import ./cli
import ./matrix
import ./matrix_gpu
import ./matrix_render

const
  PkgConfigDeps = "wayland-client"
  PkgConfigCheck = gorgeEx("pkg-config --exists " & PkgConfigDeps)

when PkgConfigCheck.exitCode != 0:
  {.error: "missing system dependencies: install pkg-config plus development packages for wayland-client".}

{.passC: "-Isrc -Isrc/lockme " & gorge("pkg-config --cflags " & PkgConfigDeps).}
{.compile: "protocols/xdg-shell-protocol.c".}
{.passL: gorge("pkg-config --libs " & PkgConfigDeps).}

const
  PreviewInitialWidth = 960'i32
  PreviewInitialHeight = 540'i32
  PreviewMinWidth = 320'i32
  PreviewMinHeight = 180'i32
  WlShmFormatXrgb8888 = 1'u32

type
  WlDisplay {.importc: "struct wl_display", header: "<wayland-client.h>", incompleteStruct.} = object
  WlRegistry {.importc: "struct wl_registry", header: "<wayland-client.h>", incompleteStruct.} = object
  WlCompositor {.importc: "struct wl_compositor", header: "<wayland-client-protocol.h>", incompleteStruct.} = object
  WlSurface {.importc: "struct wl_surface", header: "<wayland-client-protocol.h>", incompleteStruct.} = object
  WlBuffer {.importc: "struct wl_buffer", header: "<wayland-client-protocol.h>", incompleteStruct.} = object
  WlShm {.importc: "struct wl_shm", header: "<wayland-client-protocol.h>", incompleteStruct.} = object
  WlShmPool {.importc: "struct wl_shm_pool", header: "<wayland-client-protocol.h>", incompleteStruct.} = object
  WlArray {.importc: "struct wl_array", header: "<wayland-util.h>", incompleteStruct.} = object
  XdgWmBase {.importc: "struct xdg_wm_base", header: "lockme/wayland_shim.h", incompleteStruct.} = object
  XdgSurface {.importc: "struct xdg_surface", header: "lockme/wayland_shim.h", incompleteStruct.} = object
  XdgToplevel {.importc: "struct xdg_toplevel", header: "lockme/wayland_shim.h", incompleteStruct.} = object

  WlRegistryListener {.bycopy.} = object
    global: proc(data: pointer; registry: ptr WlRegistry; name: uint32; iface: cstring; version: uint32) {.cdecl.}
    globalRemove {.importc: "global_remove".}: proc(data: pointer; registry: ptr WlRegistry; name: uint32) {.cdecl.}

  WlBufferListener {.bycopy.} = object
    release: proc(data: pointer; buffer: ptr WlBuffer) {.cdecl.}

  XdgWmBaseListener {.bycopy.} = object
    ping: proc(data: pointer; wmBase: ptr XdgWmBase; serial: uint32) {.cdecl.}

  XdgSurfaceListener {.bycopy.} = object
    configure: proc(data: pointer; surface: ptr XdgSurface; serial: uint32) {.cdecl.}

  XdgToplevelListener {.bycopy.} = object
    configure: proc(data: pointer; toplevel: ptr XdgToplevel; width, height: int32; states: ptr WlArray) {.cdecl.}
    close: proc(data: pointer; toplevel: ptr XdgToplevel) {.cdecl.}
    configureBounds {.importc: "configure_bounds".}: proc(data: pointer; toplevel: ptr XdgToplevel; width, height: int32) {.cdecl.}
    wmCapabilities {.importc: "wm_capabilities".}: proc(data: pointer; toplevel: ptr XdgToplevel; capabilities: ptr WlArray) {.cdecl.}

  PreviewBuffer = object
    buffer: ptr WlBuffer
    data: ptr UncheckedArray[uint32]
    width, height: int
    size: int
    busy: bool

  Preview = ref object
    opts: Options
    running: bool
    configured: bool
    display: ptr WlDisplay
    registry: ptr WlRegistry
    compositor: ptr WlCompositor
    shm: ptr WlShm
    xdgWmBase: ptr XdgWmBase
    surface: ptr WlSurface
    xdgSurface: ptr XdgSurface
    xdgToplevel: ptr XdgToplevel
    width, height: int32
    pendingWidth, pendingHeight: int32
    renderer: MatrixRenderer
    atlas: MatrixGlyphAtlas
    rain: MatrixRain
    gpu: MatrixGpuRenderer
    gpuUnavailable: bool
    buffers: array[2, PreviewBuffer]
    blankBuffer: PreviewBuffer
    nextBuffer: int
    clockStart: MonoTime
    ticker: MatrixTicker

proc wl_display_connect(name: cstring): ptr WlDisplay {.importc, header: "<wayland-client.h>".}
proc wl_display_disconnect(display: ptr WlDisplay) {.importc, header: "<wayland-client.h>".}
proc wl_display_get_fd(display: ptr WlDisplay): cint {.importc, header: "<wayland-client.h>".}
proc wl_display_get_registry(display: ptr WlDisplay): ptr WlRegistry {.importc, header: "<wayland-client-protocol.h>".}
proc wl_display_roundtrip(display: ptr WlDisplay): cint {.importc, header: "<wayland-client.h>".}
proc wl_display_dispatch_pending(display: ptr WlDisplay): cint {.importc, header: "<wayland-client.h>".}
proc wl_display_prepare_read(display: ptr WlDisplay): cint {.importc, header: "<wayland-client.h>".}
proc wl_display_cancel_read(display: ptr WlDisplay) {.importc, header: "<wayland-client.h>".}
proc wl_display_read_events(display: ptr WlDisplay): cint {.importc, header: "<wayland-client.h>".}
proc wl_display_flush(display: ptr WlDisplay): cint {.importc, header: "<wayland-client.h>".}
proc wl_registry_destroy(registry: ptr WlRegistry) {.importc, header: "<wayland-client-protocol.h>".}
proc wl_registry_add_listener(registry: ptr WlRegistry; listener: pointer; data: pointer): cint {.importc: "lockme_wl_registry_add_listener", header: "lockme/wayland_shim.h".}
proc wl_buffer_add_listener(buffer: ptr WlBuffer; listener: pointer; data: pointer): cint {.importc: "lockme_wl_buffer_add_listener", header: "lockme/wayland_shim.h".}

proc ifaceNameWlCompositor(): cstring {.importc: "lockme_iface_name_wl_compositor", header: "lockme/wayland_shim.h".}
proc ifaceNameWlShm(): cstring {.importc: "lockme_iface_name_wl_shm", header: "lockme/wayland_shim.h".}
proc ifaceNameXdgWmBase(): cstring {.importc: "lockme_iface_name_xdg_wm_base", header: "lockme/wayland_shim.h".}

proc bindWlCompositor(registry: ptr WlRegistry; name, version: uint32): ptr WlCompositor {.importc: "lockme_registry_bind_wl_compositor", header: "lockme/wayland_shim.h".}
proc bindWlShm(registry: ptr WlRegistry; name, version: uint32): ptr WlShm {.importc: "lockme_registry_bind_wl_shm", header: "lockme/wayland_shim.h".}
proc bindXdgWmBase(registry: ptr WlRegistry; name, version: uint32): ptr XdgWmBase {.importc: "lockme_registry_bind_xdg_wm_base", header: "lockme/wayland_shim.h".}

proc wlCreateSurface(compositor: ptr WlCompositor): ptr WlSurface {.importc: "lockme_wl_compositor_create_surface", header: "lockme/wayland_shim.h".}
proc wlCompositorDestroy(compositor: ptr WlCompositor) {.importc: "lockme_wl_compositor_destroy", header: "lockme/wayland_shim.h".}
proc wlSurfaceDestroy(surface: ptr WlSurface) {.importc: "lockme_wl_surface_destroy", header: "lockme/wayland_shim.h".}
proc wlSurfaceAttach(surface: ptr WlSurface; buffer: ptr WlBuffer; x, y: int32) {.importc: "lockme_wl_surface_attach", header: "lockme/wayland_shim.h".}
proc wlSurfaceDamageBuffer(surface: ptr WlSurface; x, y, width, height: int32) {.importc: "lockme_wl_surface_damage_buffer", header: "lockme/wayland_shim.h".}
proc wlSurfaceCommit(surface: ptr WlSurface) {.importc: "lockme_wl_surface_commit", header: "lockme/wayland_shim.h".}
proc wlBufferDestroy(buffer: ptr WlBuffer) {.importc: "lockme_wl_buffer_destroy", header: "lockme/wayland_shim.h".}
proc wlShmCreatePool(shm: ptr WlShm; fd, size: int32): ptr WlShmPool {.importc: "lockme_wl_shm_create_pool", header: "lockme/wayland_shim.h".}
proc wlShmDestroy(shm: ptr WlShm) {.importc: "lockme_wl_shm_destroy", header: "lockme/wayland_shim.h".}
proc wlShmPoolCreateBuffer(pool: ptr WlShmPool; offset, width, height, stride: int32; format: uint32): ptr WlBuffer {.importc: "lockme_wl_shm_pool_create_buffer", header: "lockme/wayland_shim.h".}
proc wlShmPoolDestroy(pool: ptr WlShmPool) {.importc: "lockme_wl_shm_pool_destroy", header: "lockme/wayland_shim.h".}

proc xdgWmBaseAddListener(wmBase: ptr XdgWmBase; listener: pointer; data: pointer): cint {.importc: "lockme_xdg_wm_base_add_listener", header: "lockme/wayland_shim.h".}
proc xdgSurfaceAddListener(surface: ptr XdgSurface; listener: pointer; data: pointer): cint {.importc: "lockme_xdg_surface_add_listener", header: "lockme/wayland_shim.h".}
proc xdgToplevelAddListener(toplevel: ptr XdgToplevel; listener: pointer; data: pointer): cint {.importc: "lockme_xdg_toplevel_add_listener", header: "lockme/wayland_shim.h".}
proc xdgWmBaseDestroy(wmBase: ptr XdgWmBase) {.importc: "lockme_xdg_wm_base_destroy", header: "lockme/wayland_shim.h".}
proc xdgWmBasePong(wmBase: ptr XdgWmBase; serial: uint32) {.importc: "lockme_xdg_wm_base_pong", header: "lockme/wayland_shim.h".}
proc xdgWmBaseGetXdgSurface(wmBase: ptr XdgWmBase; surface: ptr WlSurface): ptr XdgSurface {.importc: "lockme_xdg_wm_base_get_xdg_surface", header: "lockme/wayland_shim.h".}
proc xdgSurfaceDestroy(surface: ptr XdgSurface) {.importc: "lockme_xdg_surface_destroy", header: "lockme/wayland_shim.h".}
proc xdgSurfaceAckConfigure(surface: ptr XdgSurface; serial: uint32) {.importc: "lockme_xdg_surface_ack_configure", header: "lockme/wayland_shim.h".}
proc xdgSurfaceSetWindowGeometry(surface: ptr XdgSurface; x, y, width, height: int32) {.importc: "lockme_xdg_surface_set_window_geometry", header: "lockme/wayland_shim.h".}
proc xdgSurfaceGetToplevel(surface: ptr XdgSurface): ptr XdgToplevel {.importc: "lockme_xdg_surface_get_toplevel", header: "lockme/wayland_shim.h".}
proc xdgToplevelDestroy(toplevel: ptr XdgToplevel) {.importc: "lockme_xdg_toplevel_destroy", header: "lockme/wayland_shim.h".}
proc xdgToplevelSetTitle(toplevel: ptr XdgToplevel; title: cstring) {.importc: "lockme_xdg_toplevel_set_title", header: "lockme/wayland_shim.h".}
proc xdgToplevelSetAppId(toplevel: ptr XdgToplevel; appId: cstring) {.importc: "lockme_xdg_toplevel_set_app_id", header: "lockme/wayland_shim.h".}
proc xdgToplevelSetMinSize(toplevel: ptr XdgToplevel; width, height: int32) {.importc: "lockme_xdg_toplevel_set_min_size", header: "lockme/wayland_shim.h".}

proc memfd_create(name: cstring; flags: cuint): cint {.importc, header: "<sys/mman.h>".}

var
  registryListener: WlRegistryListener
  bufferListener: WlBufferListener
  wmBaseListener: XdgWmBaseListener
  xdgSurfaceListener: XdgSurfaceListener
  xdgToplevelListener: XdgToplevelListener

proc fatal(message: string) {.noreturn.} =
  quit("lockme: " & message, 1)

proc matrixNowMs(preview: Preview; now: MonoTime): int64 =
  if preview.clockStart.ticks == 0:
    return 0
  (now - preview.clockStart).inMilliseconds

proc destroyBuffer(buf: var PreviewBuffer) =
  if not buf.data.isNil:
    discard munmap(buf.data, buf.size)
  if not buf.buffer.isNil:
    wlBufferDestroy(buf.buffer)
  buf = PreviewBuffer()

proc destroyBuffers(preview: Preview) =
  if not preview.gpu.isNil:
    preview.gpu.close()
    preview.gpu = nil
  for buf in mitems(preview.buffers):
    buf.destroyBuffer()
  preview.blankBuffer.destroyBuffer()
  preview.nextBuffer = 0
  preview.gpuUnavailable = false

proc ensureRenderer(preview: Preview): bool =
  if not preview.renderer.isNil:
    return true
  preview.renderer = initMatrixRenderer(preview.opts.matrixCellScale)
  if preview.renderer.isNil:
    return false
  preview.atlas = buildMatrixGlyphAtlas(preview.renderer)
  true

proc createGpu(preview: Preview): bool =
  if preview.width <= 0 or preview.height <= 0 or preview.surface.isNil:
    return false
  if preview.gpuUnavailable:
    return false
  if preview.gpu.isNil:
    preview.gpu = initMatrixGpuRenderer(
      cast[pointer](preview.display),
      cast[pointer](preview.surface),
      int(preview.width),
      int(preview.height),
      preview.atlas
    )
    if preview.gpu.isNil:
      stderr.writeLine("lockme: warning: preview GPU renderer unavailable: " & matrixGpuLastError())
      preview.gpuUnavailable = true
      return false
  elif not preview.gpu.resize(int(preview.width), int(preview.height)):
    stderr.writeLine("lockme: warning: preview GPU renderer resize failed: " & matrixGpuLastError())
    preview.gpu.close()
    preview.gpu = nil
    return false
  true

proc createBuffers(preview: Preview): bool =
  if preview.width <= 0 or preview.height <= 0:
    return false
  if not preview.ensureRenderer():
    stderr.writeLine("lockme: warning: failed to initialize Matrix renderer")
    return false

  let width = int(preview.width)
  let height = int(preview.height)
  if preview.createGpu():
    return true
  if preview.shm.isNil:
    stderr.writeLine("lockme: warning: wl_shm unavailable for preview CPU fallback")
    return false
  if preview.buffers[0].buffer != nil and preview.buffers[0].width == width and preview.buffers[0].height == height:
    return true

  preview.destroyBuffers()

  let geometry = matrixRenderGeometry(width, height, preview.renderer)
  if geometry.cols <= 0 or geometry.rows <= 0:
    stderr.writeLine("lockme: warning: preview window is too small for matrix cells")
    return false

  let layout = matrixShmBufferLayout(width, height)
  if not layout.valid:
    stderr.writeLine(
      "lockme: warning: preview buffer too large: " & $width & "x" & $height &
      " (max " & $MatrixShmMaxDimension & "x" & $MatrixShmMaxDimension & ")"
    )
    return false
  let size = layout.size
  let stride = layout.stride

  for i in 0 ..< preview.buffers.len:
    let buf = addr preview.buffers[i]
    let fd = memfd_create("lockme-preview".cstring, 0)
    if fd < 0:
      preview.destroyBuffers()
      stderr.writeLine("lockme: warning: memfd_create failed for preview buffer")
      return false
    if ftruncate(fd, size.Off) != 0:
      discard close(fd)
      preview.destroyBuffers()
      stderr.writeLine("lockme: warning: ftruncate failed for preview buffer")
      return false

    let mapped = mmap(nil, size, PROT_READ or PROT_WRITE, MAP_SHARED, fd, 0)
    if mapped == cast[pointer](-1):
      discard close(fd)
      preview.destroyBuffers()
      stderr.writeLine("lockme: warning: mmap failed for preview buffer")
      return false

    let pool = wlShmCreatePool(preview.shm, fd, size.int32)
    discard close(fd)
    if pool.isNil:
      discard munmap(mapped, size)
      preview.destroyBuffers()
      stderr.writeLine("lockme: warning: wl_shm pool creation failed for preview")
      return false

    let wlbuf = wlShmPoolCreateBuffer(pool, 0, width.int32, height.int32, stride.int32, WlShmFormatXrgb8888)
    wlShmPoolDestroy(pool)
    if wlbuf.isNil:
      discard munmap(mapped, size)
      preview.destroyBuffers()
      stderr.writeLine("lockme: warning: wl_shm buffer creation failed for preview")
      return false

    buf[] = PreviewBuffer(
      buffer: wlbuf,
      data: cast[ptr UncheckedArray[uint32]](mapped),
      width: width,
      height: height,
      size: size,
      busy: false
    )
    discard wl_buffer_add_listener(buf.buffer, cast[pointer](addr bufferListener), cast[pointer](buf))

  preview.rain = initMatrixRain(geometry.cols, geometry.rows)
  true

proc createBlankBuffer(preview: Preview): bool =
  if preview.width <= 0 or preview.height <= 0:
    return false
  let width = int(preview.width)
  let height = int(preview.height)
  if not preview.blankBuffer.buffer.isNil and preview.blankBuffer.width == width and preview.blankBuffer.height == height:
    return true
  preview.blankBuffer.destroyBuffer()
  if preview.shm.isNil:
    stderr.writeLine("lockme: warning: wl_shm unavailable for blank preview")
    return false
  let layout = matrixShmBufferLayout(width, height)
  if not layout.valid:
    stderr.writeLine(
      "lockme: warning: blank preview buffer too large: " & $width & "x" & $height &
      " (max " & $MatrixShmMaxDimension & "x" & $MatrixShmMaxDimension & ")"
    )
    return false
  let size = layout.size
  let stride = layout.stride
  let fd = memfd_create("lockme-preview-blank".cstring, 0)
  if fd < 0:
    stderr.writeLine("lockme: warning: memfd_create failed for blank preview buffer")
    return false
  if ftruncate(fd, size.Off) != 0:
    discard close(fd)
    stderr.writeLine("lockme: warning: ftruncate failed for blank preview buffer")
    return false
  let mapped = mmap(nil, size, PROT_READ or PROT_WRITE, MAP_SHARED, fd, 0)
  if mapped == cast[pointer](-1):
    discard close(fd)
    stderr.writeLine("lockme: warning: mmap failed for blank preview buffer")
    return false
  let pool = wlShmCreatePool(preview.shm, fd, size.int32)
  discard close(fd)
  if pool.isNil:
    discard munmap(mapped, size)
    stderr.writeLine("lockme: warning: wl_shm pool creation failed for blank preview")
    return false
  let wlbuf = wlShmPoolCreateBuffer(pool, 0, width.int32, height.int32, stride.int32, WlShmFormatXrgb8888)
  wlShmPoolDestroy(pool)
  if wlbuf.isNil:
    discard munmap(mapped, size)
    stderr.writeLine("lockme: warning: wl_shm buffer creation failed for blank preview")
    return false

  let color = 0xff000000'u32 or preview.opts.initColor
  let pixels = cast[ptr UncheckedArray[uint32]](mapped)
  for i in 0 ..< width * height:
    pixels[i] = color
  preview.blankBuffer = PreviewBuffer(
    buffer: wlbuf,
    data: pixels,
    width: width,
    height: height,
    size: size,
    busy: false
  )
  discard wl_buffer_add_listener(preview.blankBuffer.buffer, cast[pointer](addr bufferListener), cast[pointer](addr preview.blankBuffer))
  true

proc presentBlank(preview: Preview): bool =
  if not preview.configured or preview.surface.isNil or preview.xdgSurface.isNil:
    return false
  if not preview.createBlankBuffer():
    return false
  xdgSurfaceSetWindowGeometry(preview.xdgSurface, 0, 0, preview.width, preview.height)
  wlSurfaceAttach(preview.surface, preview.blankBuffer.buffer, 0, 0)
  wlSurfaceDamageBuffer(preview.surface, 0, 0, preview.width, preview.height)
  wlSurfaceCommit(preview.surface)
  preview.blankBuffer.busy = true
  true

proc presentFrame(preview: Preview): bool =
  if not preview.configured or preview.surface.isNil or preview.xdgSurface.isNil:
    return false
  if preview.opts.blank:
    return preview.presentBlank()
  if not preview.createBuffers():
    return false

  if not preview.gpu.isNil:
    xdgSurfaceSetWindowGeometry(preview.xdgSurface, 0, 0, preview.width, preview.height)
    return preview.gpu.render(
      preview.matrixNowMs(getMonoTime()),
      preview.opts.matrixFallSpeed,
      preview.opts.matrixCycleSpeed,
      preview.opts.matrixRaindropLength,
      preview.opts.matrixBrightnessDecay
    )

  for offset in 0 ..< preview.buffers.len:
    let idx = (preview.nextBuffer + offset) mod preview.buffers.len
    let buf = addr preview.buffers[idx]
    if buf.buffer.isNil or buf.data.isNil or buf.busy:
      continue

    renderMatrix(preview.rain, preview.renderer, buf.data, buf.width, buf.height)
    xdgSurfaceSetWindowGeometry(preview.xdgSurface, 0, 0, preview.width, preview.height)
    wlSurfaceAttach(preview.surface, buf.buffer, 0, 0)
    wlSurfaceDamageBuffer(preview.surface, 0, 0, preview.width, preview.height)
    wlSurfaceCommit(preview.surface)
    buf.busy = true
    preview.nextBuffer = (idx + 1) mod preview.buffers.len
    return true

  true

proc registryGlobal(data: pointer; registry: ptr WlRegistry; name: uint32; iface: cstring; version: uint32) {.cdecl.} =
  let preview = cast[Preview](data)
  let ifaceName = $iface
  if ifaceName == $ifaceNameWlCompositor() and preview.compositor.isNil:
    if version < 4:
      fatal("wl_compositor version 4 is required")
    preview.compositor = bindWlCompositor(registry, name, 4)
  elif ifaceName == $ifaceNameWlShm() and preview.shm.isNil:
    preview.shm = bindWlShm(registry, name, 1)
  elif ifaceName == $ifaceNameXdgWmBase() and preview.xdgWmBase.isNil:
    preview.xdgWmBase = bindXdgWmBase(registry, name, min(version, 6'u32))
    discard xdgWmBaseAddListener(preview.xdgWmBase, cast[pointer](addr wmBaseListener), cast[pointer](preview))

proc registryGlobalRemove(data: pointer; registry: ptr WlRegistry; name: uint32) {.cdecl.} =
  discard

proc bufferRelease(data: pointer; buffer: ptr WlBuffer) {.cdecl.} =
  let previewBuffer = cast[ptr PreviewBuffer](data)
  previewBuffer.busy = false

proc wmBasePing(data: pointer; wmBase: ptr XdgWmBase; serial: uint32) {.cdecl.} =
  xdgWmBasePong(wmBase, serial)

proc xdgSurfaceConfigure(data: pointer; surface: ptr XdgSurface; serial: uint32) {.cdecl.} =
  let preview = cast[Preview](data)
  xdgSurfaceAckConfigure(surface, serial)
  if preview.pendingWidth > 0 and preview.pendingHeight > 0 and
      (preview.pendingWidth != preview.width or preview.pendingHeight != preview.height):
    preview.width = preview.pendingWidth
    preview.height = preview.pendingHeight
    preview.destroyBuffers()
  preview.configured = true
  discard preview.presentFrame()

proc xdgToplevelConfigure(data: pointer; toplevel: ptr XdgToplevel; width, height: int32; states: ptr WlArray) {.cdecl.} =
  let preview = cast[Preview](data)
  if width > 0:
    preview.pendingWidth = width
  if height > 0:
    preview.pendingHeight = height

proc xdgToplevelClose(data: pointer; toplevel: ptr XdgToplevel) {.cdecl.} =
  let preview = cast[Preview](data)
  preview.running = false

proc xdgToplevelConfigureBounds(data: pointer; toplevel: ptr XdgToplevel; width, height: int32) {.cdecl.} =
  discard

proc xdgToplevelWmCapabilities(data: pointer; toplevel: ptr XdgToplevel; capabilities: ptr WlArray) {.cdecl.} =
  discard

proc initListeners() =
  registryListener = WlRegistryListener(global: registryGlobal, globalRemove: registryGlobalRemove)
  bufferListener = WlBufferListener(release: bufferRelease)
  wmBaseListener = XdgWmBaseListener(ping: wmBasePing)
  xdgSurfaceListener = XdgSurfaceListener(configure: xdgSurfaceConfigure)
  xdgToplevelListener = XdgToplevelListener(
    configure: xdgToplevelConfigure,
    close: xdgToplevelClose,
    configureBounds: xdgToplevelConfigureBounds,
    wmCapabilities: xdgToplevelWmCapabilities
  )

proc flushAndPrepareRead(preview: Preview) =
  while wl_display_prepare_read(preview.display) != 0:
    if wl_display_dispatch_pending(preview.display) < 0:
      fatal("failed to dispatch Wayland events")
  while true:
    let rc = wl_display_flush(preview.display)
    if rc >= 0:
      return
    if errno == EAGAIN:
      var pfd = TPollfd(fd: wl_display_get_fd(preview.display), events: POLLOUT, revents: 0)
      discard poll(addr pfd, Tnfds(1), -1)
    else:
      discard wl_display_read_events(preview.display)
      fatal("failed to flush Wayland connection")

proc deinit(preview: Preview) =
  preview.destroyBuffers()
  if not preview.xdgToplevel.isNil:
    xdgToplevelDestroy(preview.xdgToplevel)
  if not preview.xdgSurface.isNil:
    xdgSurfaceDestroy(preview.xdgSurface)
  if not preview.surface.isNil:
    wlSurfaceDestroy(preview.surface)
  if not preview.xdgWmBase.isNil:
    xdgWmBaseDestroy(preview.xdgWmBase)
  if not preview.shm.isNil:
    wlShmDestroy(preview.shm)
  if not preview.compositor.isNil:
    wlCompositorDestroy(preview.compositor)
  if not preview.registry.isNil:
    wl_registry_destroy(preview.registry)
  if not preview.display.isNil:
    wl_display_disconnect(preview.display)
  if not preview.renderer.isNil:
    preview.renderer.close()

proc connectAndCreate(opts: Options): Preview =
  result = Preview(
    opts: opts,
    running: true,
    width: PreviewInitialWidth,
    height: PreviewInitialHeight,
    pendingWidth: PreviewInitialWidth,
    pendingHeight: PreviewInitialHeight,
    clockStart: getMonoTime()
  )

  if not opts.blank:
    discard result.ensureRenderer()

  result.display = wl_display_connect(nil)
  if result.display.isNil:
    fatal("failed to connect to a Wayland compositor")
  result.registry = wl_display_get_registry(result.display)
  discard wl_registry_add_listener(result.registry, cast[pointer](addr registryListener), cast[pointer](result))
  if wl_display_roundtrip(result.display) < 0:
    fatal("initial Wayland roundtrip failed")
  if result.compositor.isNil:
    fatal("wl_compositor not advertised")
  if result.shm.isNil:
    fatal("wl_shm not advertised")
  if result.xdgWmBase.isNil:
    fatal("xdg_wm_base not advertised")

  result.surface = wlCreateSurface(result.compositor)
  if result.surface.isNil:
    fatal("failed to create preview wl_surface")
  result.xdgSurface = xdgWmBaseGetXdgSurface(result.xdgWmBase, result.surface)
  if result.xdgSurface.isNil:
    fatal("failed to create preview xdg_surface")
  discard xdgSurfaceAddListener(result.xdgSurface, cast[pointer](addr xdgSurfaceListener), cast[pointer](result))
  result.xdgToplevel = xdgSurfaceGetToplevel(result.xdgSurface)
  if result.xdgToplevel.isNil:
    fatal("failed to create preview xdg_toplevel")
  discard xdgToplevelAddListener(result.xdgToplevel, cast[pointer](addr xdgToplevelListener), cast[pointer](result))
  xdgToplevelSetTitle(result.xdgToplevel, "lockme Matrix preview".cstring)
  xdgToplevelSetAppId(result.xdgToplevel, "lockme-preview".cstring)
  xdgToplevelSetMinSize(result.xdgToplevel, PreviewMinWidth, PreviewMinHeight)
  wlSurfaceCommit(result.surface)

proc runDevWindow*(opts: Options) =
  initListeners()
  let preview = connectAndCreate(opts)
  defer: preview.deinit()

  var pollfd: TPollfd
  while preview.running:
    preview.flushAndPrepareRead()
    pollfd = TPollfd(fd: wl_display_get_fd(preview.display), events: POLLIN, revents: 0)

    let pollStart = getMonoTime()
    let matrixVisible = preview.configured and not preview.opts.blank
    let timeout = cint(matrixFrameTimeoutMs(
      preview.ticker,
      matrixVisible,
      preview.matrixNowMs(pollStart),
      preview.opts.matrixFrameMs
    ))

    let pollRc = poll(addr pollfd, Tnfds(1), timeout)
    if pollRc < 0:
      if errno == EINTR:
        wl_display_cancel_read(preview.display)
        continue
      fatal("poll failed")

    if (pollfd.revents and POLLIN) != 0:
      if wl_display_read_events(preview.display) < 0:
        fatal("failed to read Wayland events")
      while wl_display_dispatch_pending(preview.display) > 0:
        discard
    else:
      wl_display_cancel_read(preview.display)

    let frameNow = getMonoTime()
    if matrixFrameDue(
      preview.ticker,
      preview.configured and not preview.opts.blank,
      preview.matrixNowMs(frameNow),
      preview.opts.matrixFrameMs
    ):
      preview.rain.advance()
      discard preview.presentFrame()
