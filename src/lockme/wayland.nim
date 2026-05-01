import std/posix

import ./auth
import ./cli
import ./password

const
  PkgConfigDeps = "wayland-client xkbcommon pam"
  PkgConfigCheck = gorgeEx("pkg-config --exists " & PkgConfigDeps)

when PkgConfigCheck.exitCode != 0:
  {.error: "missing system dependencies: install pkg-config plus development packages for wayland-client, xkbcommon, and pam".}

{.passC: "-Isrc -Isrc/lockme " & gorge("pkg-config --cflags " & PkgConfigDeps).}
{.compile: "wayland_shim.c".}
{.compile: "protocols/ext-session-lock-v1-protocol.c".}
{.compile: "protocols/single-pixel-buffer-v1-protocol.c".}
{.compile: "protocols/viewporter-protocol.c".}
{.passL: gorge("pkg-config --libs " & PkgConfigDeps).}

const
  WlKeyboardKeyStatePressed = 1'u32
  WlSeatCapabilityPointer = 1'u32
  WlSeatCapabilityKeyboard = 2'u32

  XkbKeymapFormatTextV1 = 1.cint
  XkbKeyReturn = 0xff0d'u32
  XkbKeyKpEnter = 0xff8d'u32
  XkbKeyEscape = 0xff1b'u32
  XkbKeyBackspace = 0xff08'u32
  XkbKeyU = 0x0075'u32
  XkbStateModsDepressed = 1.cint
  XkbStateModsLatched = 2.cint

type
  WlDisplay {.importc: "struct wl_display", header: "<wayland-client.h>", incompleteStruct.} = object
  WlRegistry {.importc: "struct wl_registry", header: "<wayland-client.h>", incompleteStruct.} = object
  WlCompositor {.importc: "struct wl_compositor", header: "<wayland-client-protocol.h>", incompleteStruct.} = object
  WlSurface {.importc: "struct wl_surface", header: "<wayland-client-protocol.h>", incompleteStruct.} = object
  WlBuffer {.importc: "struct wl_buffer", header: "<wayland-client-protocol.h>", incompleteStruct.} = object
  WlOutput {.importc: "struct wl_output", header: "<wayland-client-protocol.h>", incompleteStruct.} = object
  WlShm {.importc: "struct wl_shm", header: "<wayland-client-protocol.h>", incompleteStruct.} = object
  WlShmPool {.importc: "struct wl_shm_pool", header: "<wayland-client-protocol.h>", incompleteStruct.} = object
  WlSeat {.importc: "struct wl_seat", header: "<wayland-client-protocol.h>", incompleteStruct.} = object
  WlPointer {.importc: "struct wl_pointer", header: "<wayland-client-protocol.h>", incompleteStruct.} = object
  WlKeyboard {.importc: "struct wl_keyboard", header: "<wayland-client-protocol.h>", incompleteStruct.} = object
  WlArray {.importc: "struct wl_array", header: "<wayland-util.h>", incompleteStruct.} = object
  ExtSessionLockManager {.importc: "struct ext_session_lock_manager_v1", header: "lockme/wayland_shim.h", incompleteStruct.} = object
  ExtSessionLock {.importc: "struct ext_session_lock_v1", header: "lockme/wayland_shim.h", incompleteStruct.} = object
  ExtSessionLockSurface {.importc: "struct ext_session_lock_surface_v1", header: "lockme/wayland_shim.h", incompleteStruct.} = object
  WpSinglePixelBufferManager {.importc: "struct wp_single_pixel_buffer_manager_v1", header: "lockme/wayland_shim.h", incompleteStruct.} = object
  WpViewporter {.importc: "struct wp_viewporter", header: "lockme/wayland_shim.h", incompleteStruct.} = object
  WpViewport {.importc: "struct wp_viewport", header: "lockme/wayland_shim.h", incompleteStruct.} = object

  XkbContext {.importc: "struct xkb_context", header: "<xkbcommon/xkbcommon.h>", incompleteStruct.} = object
  XkbKeymap {.importc: "struct xkb_keymap", header: "<xkbcommon/xkbcommon.h>", incompleteStruct.} = object
  XkbState {.importc: "struct xkb_state", header: "<xkbcommon/xkbcommon.h>", incompleteStruct.} = object

  WlRegistryListener {.bycopy.} = object
    global: proc(data: pointer; registry: ptr WlRegistry; name: uint32; iface: cstring; version: uint32) {.cdecl.}
    globalRemove {.importc: "global_remove".}: proc(data: pointer; registry: ptr WlRegistry; name: uint32) {.cdecl.}

  WlSeatListener {.bycopy.} = object
    capabilities: proc(data: pointer; seat: ptr WlSeat; capabilities: uint32) {.cdecl.}
    name: proc(data: pointer; seat: ptr WlSeat; name: cstring) {.cdecl.}

  WlPointerListener {.bycopy.} = object
    enter: proc(data: pointer; pointer: ptr WlPointer; serial: uint32; surface: ptr WlSurface; x, y: int32) {.cdecl.}
    leave: proc(data: pointer; pointer: ptr WlPointer; serial: uint32; surface: ptr WlSurface) {.cdecl.}
    motion: proc(data: pointer; pointer: ptr WlPointer; time: uint32; x, y: int32) {.cdecl.}
    button: proc(data: pointer; pointer: ptr WlPointer; serial, time, button, state: uint32) {.cdecl.}
    axis: proc(data: pointer; pointer: ptr WlPointer; time, axis: uint32; value: int32) {.cdecl.}
    frame: proc(data: pointer; pointer: ptr WlPointer) {.cdecl.}
    axisSource {.importc: "axis_source".}: proc(data: pointer; pointer: ptr WlPointer; axisSource: uint32) {.cdecl.}
    axisStop {.importc: "axis_stop".}: proc(data: pointer; pointer: ptr WlPointer; time, axis: uint32) {.cdecl.}
    axisDiscrete {.importc: "axis_discrete".}: proc(data: pointer; pointer: ptr WlPointer; axis: uint32; discrete: int32) {.cdecl.}
    axisValue120 {.importc: "axis_value120".}: proc(data: pointer; pointer: ptr WlPointer; axis: uint32; value120: int32) {.cdecl.}
    axisRelativeDirection {.importc: "axis_relative_direction".}: proc(data: pointer; pointer: ptr WlPointer; axis, direction: uint32) {.cdecl.}

  WlKeyboardListener {.bycopy.} = object
    keymap: proc(data: pointer; keyboard: ptr WlKeyboard; format: uint32; fd: int32; size: uint32) {.cdecl.}
    enter: proc(data: pointer; keyboard: ptr WlKeyboard; serial: uint32; surface: ptr WlSurface; keys: ptr WlArray) {.cdecl.}
    leave: proc(data: pointer; keyboard: ptr WlKeyboard; serial: uint32; surface: ptr WlSurface) {.cdecl.}
    key: proc(data: pointer; keyboard: ptr WlKeyboard; serial, time, key, state: uint32) {.cdecl.}
    modifiers: proc(data: pointer; keyboard: ptr WlKeyboard; serial, modsDepressed, modsLatched, modsLocked, group: uint32) {.cdecl.}
    repeatInfo {.importc: "repeat_info".}: proc(data: pointer; keyboard: ptr WlKeyboard; rate, delay: int32) {.cdecl.}

  ExtSessionLockListener {.bycopy.} = object
    locked: proc(data: pointer; lock: ptr ExtSessionLock) {.cdecl.}
    finished: proc(data: pointer; lock: ptr ExtSessionLock) {.cdecl.}

  ExtSessionLockSurfaceListener {.bycopy.} = object
    configure: proc(data: pointer; surface: ptr ExtSessionLockSurface; serial, width, height: uint32) {.cdecl.}

  ColorKind = enum
    ckInit, ckInput, ckFail

  ColorState = object
    kind: ColorKind
    inputIdx: int

  LockState = enum
    lsInitializing, lsLocking, lsLocked, lsExiting

  Output = ref object
    lock: Lock
    name: uint32
    wlOutput: ptr WlOutput
    surface: ptr WlSurface
    viewport: ptr WpViewport
    lockSurface: ptr ExtSessionLockSurface
    configured: bool
    width: int32
    height: int32

  Seat = ref object
    lock: Lock
    name: uint32
    wlSeat: ptr WlSeat
    pointer: ptr WlPointer
    keyboard: ptr WlKeyboard
    xkbState: ptr XkbState

  LockObj = object
    opts: Options
    state: LockState
    color: ColorState
    display: ptr WlDisplay
    compositor: ptr WlCompositor
    registry: ptr WlRegistry
    lockManager: ptr ExtSessionLockManager
    sessionLock: ptr ExtSessionLock
    viewporter: ptr WpViewporter
    pixelManager: ptr WpSinglePixelBufferManager
    shm: ptr WlShm
    buffers: seq[ptr WlBuffer]
    outputs: seq[Output]
    seats: seq[Seat]
    xkbContext: ptr XkbContext
    password: PasswordBuffer
    auth: AuthConnection

  Lock = ref LockObj

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
proc wl_seat_add_listener(seat: ptr WlSeat; listener: pointer; data: pointer): cint {.importc: "lockme_wl_seat_add_listener", header: "lockme/wayland_shim.h".}
proc wl_pointer_add_listener(pointer: ptr WlPointer; listener: pointer; data: pointer): cint {.importc: "lockme_wl_pointer_add_listener", header: "lockme/wayland_shim.h".}
proc wl_keyboard_add_listener(keyboard: ptr WlKeyboard; listener: pointer; data: pointer): cint {.importc: "lockme_wl_keyboard_add_listener", header: "lockme/wayland_shim.h".}
proc ext_session_lock_v1_add_listener(lock: ptr ExtSessionLock; listener: pointer; data: pointer): cint {.importc: "lockme_ext_session_lock_v1_add_listener", header: "lockme/wayland_shim.h".}
proc ext_session_lock_surface_v1_add_listener(surface: ptr ExtSessionLockSurface; listener: pointer; data: pointer): cint {.importc: "lockme_ext_session_lock_surface_v1_add_listener", header: "lockme/wayland_shim.h".}

proc ifaceNameWlCompositor(): cstring {.importc: "lockme_iface_name_wl_compositor", header: "lockme/wayland_shim.h".}
proc ifaceNameWlOutput(): cstring {.importc: "lockme_iface_name_wl_output", header: "lockme/wayland_shim.h".}
proc ifaceNameWlSeat(): cstring {.importc: "lockme_iface_name_wl_seat", header: "lockme/wayland_shim.h".}
proc ifaceNameWlShm(): cstring {.importc: "lockme_iface_name_wl_shm", header: "lockme/wayland_shim.h".}
proc ifaceNameLockManager(): cstring {.importc: "lockme_iface_name_ext_session_lock_manager_v1", header: "lockme/wayland_shim.h".}
proc ifaceNameViewporter(): cstring {.importc: "lockme_iface_name_wp_viewporter", header: "lockme/wayland_shim.h".}
proc ifaceNamePixelManager(): cstring {.importc: "lockme_iface_name_wp_single_pixel_buffer_manager_v1", header: "lockme/wayland_shim.h".}

proc bindWlCompositor(registry: ptr WlRegistry; name, version: uint32): ptr WlCompositor {.importc: "lockme_registry_bind_wl_compositor", header: "lockme/wayland_shim.h".}
proc bindWlOutput(registry: ptr WlRegistry; name, version: uint32): ptr WlOutput {.importc: "lockme_registry_bind_wl_output", header: "lockme/wayland_shim.h".}
proc bindWlSeat(registry: ptr WlRegistry; name, version: uint32): ptr WlSeat {.importc: "lockme_registry_bind_wl_seat", header: "lockme/wayland_shim.h".}
proc bindWlShm(registry: ptr WlRegistry; name, version: uint32): ptr WlShm {.importc: "lockme_registry_bind_wl_shm", header: "lockme/wayland_shim.h".}
proc bindLockManager(registry: ptr WlRegistry; name, version: uint32): ptr ExtSessionLockManager {.importc: "lockme_registry_bind_ext_session_lock_manager_v1", header: "lockme/wayland_shim.h".}
proc bindViewporter(registry: ptr WlRegistry; name, version: uint32): ptr WpViewporter {.importc: "lockme_registry_bind_wp_viewporter", header: "lockme/wayland_shim.h".}
proc bindPixelManager(registry: ptr WlRegistry; name, version: uint32): ptr WpSinglePixelBufferManager {.importc: "lockme_registry_bind_wp_single_pixel_buffer_manager_v1", header: "lockme/wayland_shim.h".}

proc wlCreateSurface(compositor: ptr WlCompositor): ptr WlSurface {.importc: "lockme_wl_compositor_create_surface", header: "lockme/wayland_shim.h".}
proc wlCompositorDestroy(compositor: ptr WlCompositor) {.importc: "lockme_wl_compositor_destroy", header: "lockme/wayland_shim.h".}
proc wlSurfaceDestroy(surface: ptr WlSurface) {.importc: "lockme_wl_surface_destroy", header: "lockme/wayland_shim.h".}
proc wlSurfaceAttach(surface: ptr WlSurface; buffer: ptr WlBuffer; x, y: int32) {.importc: "lockme_wl_surface_attach", header: "lockme/wayland_shim.h".}
proc wlSurfaceDamageBuffer(surface: ptr WlSurface; x, y, width, height: int32) {.importc: "lockme_wl_surface_damage_buffer", header: "lockme/wayland_shim.h".}
proc wlSurfaceCommit(surface: ptr WlSurface) {.importc: "lockme_wl_surface_commit", header: "lockme/wayland_shim.h".}
proc wlBufferDestroy(buffer: ptr WlBuffer) {.importc: "lockme_wl_buffer_destroy", header: "lockme/wayland_shim.h".}
proc wlOutputRelease(output: ptr WlOutput) {.importc: "lockme_wl_output_release", header: "lockme/wayland_shim.h".}
proc wlShmCreatePool(shm: ptr WlShm; fd, size: int32): ptr WlShmPool {.importc: "lockme_wl_shm_create_pool", header: "lockme/wayland_shim.h".}
proc wlShmDestroy(shm: ptr WlShm) {.importc: "lockme_wl_shm_destroy", header: "lockme/wayland_shim.h".}
proc wlShmPoolCreateBuffer(pool: ptr WlShmPool; offset, width, height, stride: int32; format: uint32): ptr WlBuffer {.importc: "lockme_wl_shm_pool_create_buffer", header: "lockme/wayland_shim.h".}
proc wlShmPoolDestroy(pool: ptr WlShmPool) {.importc: "lockme_wl_shm_pool_destroy", header: "lockme/wayland_shim.h".}
proc wlSeatGetPointer(seat: ptr WlSeat): ptr WlPointer {.importc: "lockme_wl_seat_get_pointer", header: "lockme/wayland_shim.h".}
proc wlSeatGetKeyboard(seat: ptr WlSeat): ptr WlKeyboard {.importc: "lockme_wl_seat_get_keyboard", header: "lockme/wayland_shim.h".}
proc wlSeatRelease(seat: ptr WlSeat) {.importc: "lockme_wl_seat_release", header: "lockme/wayland_shim.h".}
proc wlPointerRelease(pointer: ptr WlPointer) {.importc: "lockme_wl_pointer_release", header: "lockme/wayland_shim.h".}
proc wlPointerSetCursor(pointer: ptr WlPointer; serial: uint32; surface: ptr WlSurface; x, y: int32) {.importc: "lockme_wl_pointer_set_cursor", header: "lockme/wayland_shim.h".}
proc wlKeyboardRelease(keyboard: ptr WlKeyboard) {.importc: "lockme_wl_keyboard_release", header: "lockme/wayland_shim.h".}

proc lockManagerLock(manager: ptr ExtSessionLockManager): ptr ExtSessionLock {.importc: "lockme_ext_session_lock_manager_v1_lock", header: "lockme/wayland_shim.h".}
proc lockManagerDestroy(manager: ptr ExtSessionLockManager) {.importc: "lockme_ext_session_lock_manager_v1_destroy", header: "lockme/wayland_shim.h".}
proc sessionLockDestroy(lock: ptr ExtSessionLock) {.importc: "lockme_ext_session_lock_v1_destroy", header: "lockme/wayland_shim.h".}
proc sessionLockUnlockAndDestroy(lock: ptr ExtSessionLock) {.importc: "lockme_ext_session_lock_v1_unlock_and_destroy", header: "lockme/wayland_shim.h".}
proc sessionLockGetSurface(lock: ptr ExtSessionLock; surface: ptr WlSurface; output: ptr WlOutput): ptr ExtSessionLockSurface {.importc: "lockme_ext_session_lock_v1_get_lock_surface", header: "lockme/wayland_shim.h".}
proc lockSurfaceDestroy(surface: ptr ExtSessionLockSurface) {.importc: "lockme_ext_session_lock_surface_v1_destroy", header: "lockme/wayland_shim.h".}
proc lockSurfaceAckConfigure(surface: ptr ExtSessionLockSurface; serial: uint32) {.importc: "lockme_ext_session_lock_surface_v1_ack_configure", header: "lockme/wayland_shim.h".}
proc pixelCreateBuffer(manager: ptr WpSinglePixelBufferManager; r, g, b, a: uint32): ptr WlBuffer {.importc: "lockme_wp_single_pixel_buffer_manager_v1_create_u32_rgba_buffer", header: "lockme/wayland_shim.h".}
proc pixelManagerDestroy(manager: ptr WpSinglePixelBufferManager) {.importc: "lockme_wp_single_pixel_buffer_manager_v1_destroy", header: "lockme/wayland_shim.h".}
proc viewporterGetViewport(viewporter: ptr WpViewporter; surface: ptr WlSurface): ptr WpViewport {.importc: "lockme_wp_viewporter_get_viewport", header: "lockme/wayland_shim.h".}
proc viewporterDestroy(viewporter: ptr WpViewporter) {.importc: "lockme_wp_viewporter_destroy", header: "lockme/wayland_shim.h".}
proc viewportDestroy(viewport: ptr WpViewport) {.importc: "lockme_wp_viewport_destroy", header: "lockme/wayland_shim.h".}
proc viewportSetDestination(viewport: ptr WpViewport; width, height: int32) {.importc: "lockme_wp_viewport_set_destination", header: "lockme/wayland_shim.h".}

proc xkb_context_new(flags: cint): ptr XkbContext {.importc, header: "<xkbcommon/xkbcommon.h>".}
proc xkb_context_unref(context: ptr XkbContext) {.importc, header: "<xkbcommon/xkbcommon.h>".}
proc xkb_keymap_new_from_buffer(context: ptr XkbContext; buffer: cstring; length: csize_t; format, flags: cint): ptr XkbKeymap {.importc, header: "<xkbcommon/xkbcommon.h>".}
proc xkb_keymap_unref(keymap: ptr XkbKeymap) {.importc, header: "<xkbcommon/xkbcommon.h>".}
proc xkb_state_new(keymap: ptr XkbKeymap): ptr XkbState {.importc, header: "<xkbcommon/xkbcommon.h>".}
proc xkb_state_ref(state: ptr XkbState): ptr XkbState {.importc, header: "<xkbcommon/xkbcommon.h>".}
proc xkb_state_unref(state: ptr XkbState) {.importc, header: "<xkbcommon/xkbcommon.h>".}
proc xkb_state_update_mask(state: ptr XkbState; depressed, latched, locked, depressedLayout, latchedLayout, lockedLayout: uint32): cint {.importc, header: "<xkbcommon/xkbcommon.h>".}
proc xkb_state_key_get_one_sym(state: ptr XkbState; keycode: uint32): uint32 {.importc, header: "<xkbcommon/xkbcommon.h>".}
proc xkb_state_key_get_utf8(state: ptr XkbState; keycode: uint32; buffer: cstring; size: csize_t): cint {.importc, header: "<xkbcommon/xkbcommon.h>".}
proc xkb_state_mod_name_is_active(state: ptr XkbState; name: cstring; kind: cint): cint {.importc, header: "<xkbcommon/xkbcommon.h>".}
proc memfd_create(name: cstring; flags: cuint): cint {.importc, header: "<sys/mman.h>".}
proc prctl(option: cint; arg2, arg3, arg4, arg5: culong): cint
  {.importc, header: "<sys/prctl.h>", varargs.}
proc explicit_bzero(p: pointer; n: csize_t) {.importc, header: "<string.h>".}
proc mlockall(flags: cint): cint {.importc, header: "<sys/mman.h>".}
proc setrlimit(resource: cint; rlim: ptr RLimit): cint {.importc, header: "<sys/resource.h>".}

const
  PrSetDumpable = 4.cint
  PrSetNoNewPrivs = 38.cint
  MclCurrent = 1.cint
  MclFuture = 2.cint
  RlimitCoreId = 4.cint  # Linux: RLIMIT_CORE
  WlShmFormatXrgb8888 = 1'u32

var
  registryListener: WlRegistryListener
  seatListener: WlSeatListener
  pointerListener: WlPointerListener
  keyboardListener: WlKeyboardListener
  sessionLockListener: ExtSessionLockListener
  lockSurfaceListener: ExtSessionLockSurfaceListener

proc fatal(message: string) {.noreturn.} =
  quit("lockme: " & message, 1)

proc rgba16(value: uint32; shift: int): uint32 =
  let component = (value shr shift) and 0xff'u32
  component * (0xffffffff'u32 div 0xff'u32)

proc bufferIndex(lock: Lock; color: ColorState): int =
  ## Buffer layout: [init, fail, input0, input1, ...].
  case color.kind
  of ckInit: 0
  of ckFail: 1
  of ckInput: 2 + color.inputIdx

proc initState(): ColorState = ColorState(kind: ckInit, inputIdx: 0)
proc failState(): ColorState = ColorState(kind: ckFail, inputIdx: 0)
proc inputState(idx: int): ColorState = ColorState(kind: ckInput, inputIdx: idx)

proc nextInputState(lock: Lock): ColorState =
  ## Rotate through the input palette. Wraps after the last entry.
  let n = lock.opts.inputColors.len
  if n <= 0:
    return initState()
  let nextIdx =
    if lock.color.kind == ckInput: (lock.color.inputIdx + 1) mod n
    else: 0
  inputState(nextIdx)

proc attachBuffer(output: Output; buffer: ptr WlBuffer) =
  if not output.configured or output.surface.isNil:
    return
  wlSurfaceAttach(output.surface, buffer, 0, 0)
  wlSurfaceDamageBuffer(output.surface, 0, 0, high(int32), high(int32))
  viewportSetDestination(output.viewport, output.width, output.height)
  wlSurfaceCommit(output.surface)

proc setColor(lock: Lock; color: ColorState) =
  if lock.color == color:
    return
  lock.color = color
  let idx = lock.bufferIndex(color)
  for output in lock.outputs:
    output.attachBuffer(lock.buffers[idx])

proc createOutputSurface(output: Output) =
  let lock = output.lock
  output.surface = wlCreateSurface(lock.compositor)
  if output.surface.isNil:
    fatal("failed to create wl_surface")
  output.lockSurface = sessionLockGetSurface(lock.sessionLock, output.surface, output.wlOutput)
  if output.lockSurface.isNil:
    fatal("failed to create session lock surface")
  discard ext_session_lock_surface_v1_add_listener(output.lockSurface, cast[pointer](addr lockSurfaceListener), cast[pointer](output))
  output.viewport = viewporterGetViewport(lock.viewporter, output.surface)
  if output.viewport.isNil:
    fatal("failed to create viewport")

proc destroyOutput(output: Output) =
  if not output.lockSurface.isNil:
    lockSurfaceDestroy(output.lockSurface)
  if not output.viewport.isNil:
    viewportDestroy(output.viewport)
  if not output.surface.isNil:
    wlSurfaceDestroy(output.surface)
  if not output.wlOutput.isNil:
    wlOutputRelease(output.wlOutput)

proc destroySeat(seat: Seat) =
  if not seat.xkbState.isNil:
    xkb_state_unref(seat.xkbState)
  if not seat.pointer.isNil:
    wlPointerRelease(seat.pointer)
  if not seat.keyboard.isNil:
    wlKeyboardRelease(seat.keyboard)
  if not seat.wlSeat.isNil:
    wlSeatRelease(seat.wlSeat)

proc createSolidPixelBuffer(lock: Lock; rgb: uint32): ptr WlBuffer =
  pixelCreateBuffer(
    lock.pixelManager,
    rgba16(rgb, 16),
    rgba16(rgb, 8),
    rgba16(rgb, 0),
    0xffffffff'u32
  )

proc createSolidShmBuffer(lock: Lock; rgb: uint32): ptr WlBuffer =
  let fd = memfd_create("lockme-color".cstring, 0)
  if fd < 0:
    fatal("failed to create shm buffer fd")
  if ftruncate(fd, 4) != 0:
    discard close(fd)
    fatal("failed to size shm buffer fd")
  let mapped = mmap(nil, 4, PROT_READ or PROT_WRITE, MAP_SHARED, fd, 0)
  if mapped == cast[pointer](-1):
    discard close(fd)
    fatal("failed to map shm buffer")
  cast[ptr uint32](mapped)[] = 0xff000000'u32 or rgb
  discard munmap(mapped, 4)
  let pool = wlShmCreatePool(lock.shm, fd, 4)
  discard close(fd)
  if pool.isNil:
    fatal("failed to create wl_shm pool")
  result = wlShmPoolCreateBuffer(pool, 0, 1, 1, 4, WlShmFormatXrgb8888)
  wlShmPoolDestroy(pool)

proc createBuffer(lock: Lock; rgb: uint32): ptr WlBuffer =
  if not lock.pixelManager.isNil:
    return lock.createSolidPixelBuffer(rgb)
  lock.createSolidShmBuffer(rgb)

proc createBuffers(lock: Lock) =
  let total = 2 + lock.opts.inputColors.len
  lock.buffers.setLen(total)
  lock.buffers[0] = lock.createBuffer(lock.opts.initColor)
  lock.buffers[1] = lock.createBuffer(lock.opts.failColor)
  for i, rgb in lock.opts.inputColors:
    lock.buffers[2 + i] = lock.createBuffer(rgb)
  for buf in lock.buffers:
    if buf.isNil:
      fatal("failed to create color buffer")

proc registryGlobal(data: pointer; registry: ptr WlRegistry; name: uint32; iface: cstring; version: uint32) {.cdecl.} =
  let lock = cast[Lock](data)
  let ifaceName = $iface

  if ifaceName == $ifaceNameWlCompositor():
    if version < 4:
      fatal("wl_compositor version 4 is required")
    lock.compositor = bindWlCompositor(registry, name, 4)
  elif ifaceName == $ifaceNameWlOutput():
    if version < 3:
      fatal("wl_output version 3 is required")
    let output = Output(lock: lock, name: name, wlOutput: bindWlOutput(registry, name, 3))
    lock.outputs.add(output)
    if lock.state in {lsLocking, lsLocked}:
      output.createOutputSurface()
  elif ifaceName == $ifaceNameWlSeat():
    if version < 5:
      fatal("wl_seat version 5 is required")
    let seat = Seat(lock: lock, name: name, wlSeat: bindWlSeat(registry, name, 5))
    lock.seats.add(seat)
    discard wl_seat_add_listener(seat.wlSeat, cast[pointer](addr seatListener), cast[pointer](seat))
  elif ifaceName == $ifaceNameWlShm():
    lock.shm = bindWlShm(registry, name, 1)
  elif ifaceName == $ifaceNameLockManager():
    lock.lockManager = bindLockManager(registry, name, 1)
  elif ifaceName == $ifaceNameViewporter():
    lock.viewporter = bindViewporter(registry, name, 1)
  elif ifaceName == $ifaceNamePixelManager():
    lock.pixelManager = bindPixelManager(registry, name, 1)

proc registryGlobalRemove(data: pointer; registry: ptr WlRegistry; name: uint32) {.cdecl.} =
  let lock = cast[Lock](data)
  for i, output in lock.outputs:
    if output.name == name:
      output.destroyOutput()
      lock.outputs.delete(i)
      return
  for i, seat in lock.seats:
    if seat.name == name:
      seat.destroySeat()
      lock.seats.delete(i)
      return

proc seatName(data: pointer; seat: ptr WlSeat; name: cstring) {.cdecl.} =
  discard

proc pointerEnter(data: pointer; pointer: ptr WlPointer; serial: uint32; surface: ptr WlSurface; x, y: int32) {.cdecl.} =
  wlPointerSetCursor(pointer, serial, nil, 0, 0)

proc pointerIgnore(data: pointer; pointer: ptr WlPointer) {.cdecl.} = discard
proc pointerIgnoreLeave(data: pointer; pointer: ptr WlPointer; serial: uint32; surface: ptr WlSurface) {.cdecl.} = discard
proc pointerIgnoreMotion(data: pointer; pointer: ptr WlPointer; time: uint32; x, y: int32) {.cdecl.} = discard
proc pointerIgnoreButton(data: pointer; pointer: ptr WlPointer; serial, time, button, state: uint32) {.cdecl.} = discard
proc pointerIgnoreAxis(data: pointer; pointer: ptr WlPointer; time, axis: uint32; value: int32) {.cdecl.} = discard
proc pointerIgnoreAxisSource(data: pointer; pointer: ptr WlPointer; axisSource: uint32) {.cdecl.} = discard
proc pointerIgnoreAxisStop(data: pointer; pointer: ptr WlPointer; time, axis: uint32) {.cdecl.} = discard
proc pointerIgnoreAxisDiscrete(data: pointer; pointer: ptr WlPointer; axis: uint32; discrete: int32) {.cdecl.} = discard
proc pointerIgnoreAxisValue120(data: pointer; pointer: ptr WlPointer; axis: uint32; value120: int32) {.cdecl.} = discard
proc pointerIgnoreAxisRelativeDirection(data: pointer; pointer: ptr WlPointer; axis, direction: uint32) {.cdecl.} = discard

const KeymapSizeMax = 1024 * 1024  # 1 MiB sanity cap on compositor-supplied keymap

proc keyboardKeymap(data: pointer; keyboard: ptr WlKeyboard; format: uint32; fd: int32; size: uint32) {.cdecl.} =
  let seat = cast[Seat](data)
  defer: discard close(fd)
  if format != uint32(XkbKeymapFormatTextV1):
    return
  if size == 0 or size > uint32(KeymapSizeMax):
    return
  let mapped = mmap(nil, int(size), PROT_READ, MAP_PRIVATE, cint(fd), 0)
  if mapped == cast[pointer](-1):
    return
  defer: discard munmap(mapped, int(size))
  # The Wayland protocol guarantees a trailing NUL within the mapped region,
  # so we pass `size - 1` as the length to xkb_keymap_new_from_buffer.
  let length = csize_t(size) - 1
  let keymap = xkb_keymap_new_from_buffer(seat.lock.xkbContext, cast[cstring](mapped), length, XkbKeymapFormatTextV1, 0)
  if keymap.isNil:
    return
  defer: xkb_keymap_unref(keymap)
  let state = xkb_state_new(keymap)
  if state.isNil:
    return
  if not seat.xkbState.isNil:
    xkb_state_unref(seat.xkbState)
  seat.xkbState = xkb_state_ref(state)
  xkb_state_unref(state)

proc keyboardEnter(data: pointer; keyboard: ptr WlKeyboard; serial: uint32; surface: ptr WlSurface; keys: ptr WlArray) {.cdecl.} = discard
proc keyboardLeave(data: pointer; keyboard: ptr WlKeyboard; serial: uint32; surface: ptr WlSurface) {.cdecl.} = discard
proc keyboardRepeatInfo(data: pointer; keyboard: ptr WlKeyboard; rate, delay: int32) {.cdecl.} = discard

proc keyboardModifiers(data: pointer; keyboard: ptr WlKeyboard; serial, modsDepressed, modsLatched, modsLocked, group: uint32) {.cdecl.} =
  let seat = cast[Seat](data)
  if not seat.xkbState.isNil:
    discard xkb_state_update_mask(seat.xkbState, modsDepressed, modsLatched, modsLocked, 0, 0, group)

proc submitPassword(lock: Lock) =
  if lock.state != lsLocked:
    return
  if lock.opts.ignoreEmptyPassword and lock.password.len == 0:
    return
  if not sendPassword(lock.auth, lock.password.bytesPtr, lock.password.len):
    fatal("failed to send password to auth child")
  lock.password.clear()

proc devEscape(lock: Lock) =
  if lock.state != lsLocked:
    return
  lock.password.clear()
  sessionLockUnlockAndDestroy(lock.sessionLock)
  lock.sessionLock = nil
  lock.state = lsExiting

proc keyboardKey(data: pointer; keyboard: ptr WlKeyboard; serial, time, key, state: uint32) {.cdecl.} =
  if state != WlKeyboardKeyStatePressed:
    return
  let seat = cast[Seat](data)
  let lock = seat.lock
  if lock.state == lsExiting or seat.xkbState.isNil:
    return

  let keycode = key + 8
  let sym = xkb_state_key_get_one_sym(seat.xkbState, keycode)
  case sym
  of XkbKeyReturn, XkbKeyKpEnter:
    lock.submitPassword()
  of XkbKeyEscape:
    if lock.opts.devMode:
      lock.devEscape()
    else:
      lock.password.clear()
      lock.setColor(initState())
  of XkbKeyBackspace:
    lock.password.popCodepoint()
    if lock.password.len == 0:
      lock.setColor(initState())
  of XkbKeyU:
    if xkb_state_mod_name_is_active(seat.xkbState, "Control".cstring, XkbStateModsDepressed or XkbStateModsLatched) == 1:
      lock.password.clear()
      lock.setColor(initState())
      return
    var buffer: array[64, byte]
    let written = xkb_state_key_get_utf8(seat.xkbState, keycode, cast[cstring](addr buffer[0]), csize_t(buffer.len))
    if written > 0 and int(written) < buffer.len:
      if lock.password.appendUtf8(buffer.toOpenArray(0, int(written) - 1)):
        lock.setColor(lock.nextInputState())
    explicit_bzero(addr buffer[0], csize_t(buffer.len))
  else:
    var buffer: array[64, byte]
    let written = xkb_state_key_get_utf8(seat.xkbState, keycode, cast[cstring](addr buffer[0]), csize_t(buffer.len))
    if written > 0 and int(written) < buffer.len:
      if lock.password.appendUtf8(buffer.toOpenArray(0, int(written) - 1)):
        lock.setColor(lock.nextInputState())
    explicit_bzero(addr buffer[0], csize_t(buffer.len))

proc seatCapabilities(data: pointer; wlSeat: ptr WlSeat; capabilities: uint32) {.cdecl.} =
  let seat = cast[Seat](data)
  if (capabilities and WlSeatCapabilityPointer) != 0 and seat.pointer.isNil:
    seat.pointer = wlSeatGetPointer(wlSeat)
    discard wl_pointer_add_listener(seat.pointer, cast[pointer](addr pointerListener), nil)
  elif (capabilities and WlSeatCapabilityPointer) == 0 and not seat.pointer.isNil:
    wlPointerRelease(seat.pointer)
    seat.pointer = nil

  if (capabilities and WlSeatCapabilityKeyboard) != 0 and seat.keyboard.isNil:
    seat.keyboard = wlSeatGetKeyboard(wlSeat)
    discard wl_keyboard_add_listener(seat.keyboard, cast[pointer](addr keyboardListener), cast[pointer](seat))
  elif (capabilities and WlSeatCapabilityKeyboard) == 0 and not seat.keyboard.isNil:
    wlKeyboardRelease(seat.keyboard)
    seat.keyboard = nil
    if not seat.xkbState.isNil:
      xkb_state_unref(seat.xkbState)
      seat.xkbState = nil

proc redirectStdioToDevNull() =
  let fd = open("/dev/null".cstring, O_RDWR)
  if fd < 0:
    return
  discard dup2(fd, 0.cint)
  discard dup2(fd, 1.cint)
  discard dup2(fd, 2.cint)
  if fd > 2:
    discard close(fd)

proc sessionLocked(data: pointer; sessionLock: ptr ExtSessionLock) {.cdecl.} =
  let lock = cast[Lock](data)
  lock.state = lsLocked
  if lock.opts.hasReadyFd:
    discard write(lock.opts.readyFd.cint, "\n".cstring, 1)
    discard close(lock.opts.readyFd.cint)
    lock.opts.hasReadyFd = false
  if lock.opts.forkOnLock:
    let pid = fork()
    if pid < 0:
      fatal("fork failed")
    if pid > 0:
      quit(0)
    discard setsid()
    discard chdir("/")
    redirectStdioToDevNull()
    # Re-apply mlock and MADV_DONTDUMP to the password buffer in the
    # background process; both are inherited across fork on Linux but we
    # re-apply defensively to match waylock's behavior.
    lock.password.protectAfterFork()

proc sessionFinished(data: pointer; sessionLock: ptr ExtSessionLock) {.cdecl.} =
  let lock = cast[Lock](data)
  if lock.state == lsLocking:
    fatal("compositor denied session lock; another locker may already be running")
  lock.state = lsExiting

proc lockSurfaceConfigure(data: pointer; surface: ptr ExtSessionLockSurface; serial, width, height: uint32) {.cdecl.} =
  let output = cast[Output](data)
  output.configured = true
  output.width = int32(min(width, uint32(high(int32))))
  output.height = int32(min(height, uint32(high(int32))))
  lockSurfaceAckConfigure(surface, serial)
  output.attachBuffer(output.lock.buffers[output.lock.bufferIndex(output.lock.color)])

proc flushAndPrepareRead(lock: Lock) =
  while wl_display_prepare_read(lock.display) != 0:
    if wl_display_dispatch_pending(lock.display) < 0:
      fatal("failed to dispatch Wayland events")
  while true:
    let rc = wl_display_flush(lock.display)
    if rc >= 0:
      return
    if errno == EAGAIN:
      var pfd = TPollfd(fd: wl_display_get_fd(lock.display), events: POLLOUT, revents: 0)
      discard poll(addr pfd, Tnfds(1), -1)
    else:
      discard wl_display_read_events(lock.display)
      fatal("failed to flush Wayland connection")

proc checkRequired(lock: Lock) =
  if lock.compositor.isNil: fatal("wl_compositor not advertised")
  if lock.lockManager.isNil: fatal("ext_session_lock_manager_v1 not advertised")
  if lock.viewporter.isNil: fatal("wp_viewporter not advertised")
  if lock.pixelManager.isNil and lock.shm.isNil: fatal("neither wp_single_pixel_buffer_manager_v1 nor wl_shm is advertised")

proc initListeners() =
  registryListener = WlRegistryListener(global: registryGlobal, globalRemove: registryGlobalRemove)
  seatListener = WlSeatListener(capabilities: seatCapabilities, name: seatName)
  pointerListener = WlPointerListener(
    enter: pointerEnter,
    leave: pointerIgnoreLeave,
    motion: pointerIgnoreMotion,
    button: pointerIgnoreButton,
    axis: pointerIgnoreAxis,
    frame: pointerIgnore,
    axisSource: pointerIgnoreAxisSource,
    axisStop: pointerIgnoreAxisStop,
    axisDiscrete: pointerIgnoreAxisDiscrete,
    axisValue120: pointerIgnoreAxisValue120,
    axisRelativeDirection: pointerIgnoreAxisRelativeDirection
  )
  keyboardListener = WlKeyboardListener(
    keymap: keyboardKeymap,
    enter: keyboardEnter,
    leave: keyboardLeave,
    key: keyboardKey,
    modifiers: keyboardModifiers,
    repeatInfo: keyboardRepeatInfo
  )
  sessionLockListener = ExtSessionLockListener(locked: sessionLocked, finished: sessionFinished)
  lockSurfaceListener = ExtSessionLockSurfaceListener(configure: lockSurfaceConfigure)

proc deinit(lock: Lock) =
  for output in lock.outputs:
    output.destroyOutput()
  for seat in lock.seats:
    seat.destroySeat()
  for buffer in lock.buffers:
    if not buffer.isNil:
      wlBufferDestroy(buffer)
  if not lock.sessionLock.isNil and lock.state != lsLocked:
    sessionLockDestroy(lock.sessionLock)
  if not lock.lockManager.isNil:
    lockManagerDestroy(lock.lockManager)
  if not lock.pixelManager.isNil:
    pixelManagerDestroy(lock.pixelManager)
  if not lock.shm.isNil:
    wlShmDestroy(lock.shm)
  if not lock.viewporter.isNil:
    viewporterDestroy(lock.viewporter)
  if not lock.compositor.isNil:
    wlCompositorDestroy(lock.compositor)
  if not lock.registry.isNil:
    wl_registry_destroy(lock.registry)
  if not lock.xkbContext.isNil:
    xkb_context_unref(lock.xkbContext)
  if not lock.display.isNil:
    wl_display_disconnect(lock.display)
  lock.password.clear()

proc connectAndDiscover(opts: Options): Lock =
  result = Lock(
    opts: opts,
    state: lsInitializing,
    color: initState(),
    password: initPasswordBuffer()
  )
  result.display = wl_display_connect(nil)
  if result.display.isNil:
    fatal("failed to connect to a Wayland compositor")
  result.xkbContext = xkb_context_new(0)
  if result.xkbContext.isNil:
    fatal("failed to create xkb context")
  result.registry = wl_display_get_registry(result.display)
  discard wl_registry_add_listener(result.registry, cast[pointer](addr registryListener), cast[pointer](result))
  if wl_display_roundtrip(result.display) < 0:
    fatal("initial Wayland roundtrip failed")

proc checkProtocols*(opts: Options) =
  initListeners()
  let lock = connectAndDiscover(opts)
  defer: lock.deinit()
  lock.checkRequired()
  echo "lockme: required Wayland protocols are available"

proc applyProcessHardening() =
  ## Process-wide hardening applied at startup. Each step is best-effort:
  ## a missing kernel feature must not stop the locker from running.
  ##
  ## - PR_SET_DUMPABLE=0: blocks ptrace and /proc snooping by other
  ##   same-UID processes.
  ## - RLIMIT_CORE=0: suppresses core dumps for the whole process.
  ## - mlockall(MCL_CURRENT | MCL_FUTURE): locks all current and future
  ##   pages into RAM so transient password material on the stack or in
  ##   libc internals cannot be paged to swap.
  discard prctl(PrSetDumpable, 0.culong, 0.culong, 0.culong, 0.culong)
  var rl = RLimit(rlim_cur: 0, rlim_max: 0)
  discard setrlimit(RlimitCoreId, addr rl)
  # mlockall may fail with EPERM under low RLIMIT_MEMLOCK or in
  # containers; the password buffer's own mlock is mandatory and handled
  # separately, so a failure here only weakens defense-in-depth.
  if mlockall(MclCurrent or MclFuture) != 0:
    stderr.writeLine("lockme: warning: mlockall failed; transient password material may be paged to swap (raise RLIMIT_MEMLOCK)")

proc applyParentNoNewPrivs() =
  ## Apply after forkAuthChild(). PAM may need setuid helpers such as
  ## unix_chkpwd; no_new_privs would make those helpers ineffective if
  ## inherited by the auth child.
  discard prctl(PrSetNoNewPrivs, 1.culong, 0.culong, 0.culong, 0.culong)

proc runLock*(opts: Options) =
  applyProcessHardening()
  initListeners()
  let lock = connectAndDiscover(opts)
  defer: lock.deinit()
  lock.checkRequired()
  lock.auth = forkAuthChild()
  applyParentNoNewPrivs()
  lock.createBuffers()
  if not lock.pixelManager.isNil:
    pixelManagerDestroy(lock.pixelManager)
    lock.pixelManager = nil

  lock.sessionLock = lockManagerLock(lock.lockManager)
  if lock.sessionLock.isNil:
    fatal("failed to create session lock")
  discard ext_session_lock_v1_add_listener(lock.sessionLock, cast[pointer](addr sessionLockListener), cast[pointer](lock))
  lockManagerDestroy(lock.lockManager)
  lock.lockManager = nil
  lock.state = lsLocking

  for output in lock.outputs:
    output.createOutputSurface()

  var pollfds: array[2, TPollfd]
  while lock.state != lsExiting:
    lock.flushAndPrepareRead()
    pollfds[0] = TPollfd(fd: wl_display_get_fd(lock.display), events: POLLIN, revents: 0)
    pollfds[1] = TPollfd(fd: lock.auth.readFd, events: POLLIN, revents: 0)
    if poll(addr pollfds[0], Tnfds(pollfds.len), -1) < 0:
      fatal("poll failed")

    if (pollfds[0].revents and POLLIN) != 0:
      if wl_display_read_events(lock.display) < 0:
        fatal("failed to read Wayland events")
      while wl_display_dispatch_pending(lock.display) > 0: discard
    else:
      wl_display_cancel_read(lock.display)

    if (pollfds[1].revents and POLLIN) != 0:
      var ok = false
      if not readAuthResult(lock.auth, ok):
        fatal("failed to read auth result")
      if ok:
        sessionLockUnlockAndDestroy(lock.sessionLock)
        lock.sessionLock = nil
        lock.state = lsExiting
      else:
        lock.setColor(failState())
    elif (pollfds[1].revents and (POLLHUP or POLLERR or POLLNVAL)) != 0:
      fatal("auth child exited unexpectedly")

  if wl_display_roundtrip(lock.display) < 0:
    fatal("final Wayland roundtrip failed")
