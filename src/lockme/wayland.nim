import std/[monotimes, posix, times]

import ./auth
import ./cli
import ./matrix
import ./matrix_gpu
import ./matrix_render
import ./password

const
  PkgConfigDeps = "wayland-client xkbcommon pam"
  PkgConfigCheck = gorgeEx("pkg-config --exists " & PkgConfigDeps)

when PkgConfigCheck.exitCode != 0:
  {.
    error:
      "missing system dependencies: install pkg-config plus development packages for wayland-client, xkbcommon, and pam"
  .}

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
  MatrixFailHoldMs = 750

  XkbKeymapFormatTextV1 = 1.cint
  XkbKeyReturn = 0xff0d'u32
  XkbKeyKpEnter = 0xff8d'u32
  XkbKeyEscape = 0xff1b'u32
  XkbKeyBackspace = 0xff08'u32
  XkbKeyB = 0x0042'u32
  XkbKeyLowerB = 0x0062'u32
  XkbKeyU = 0x0075'u32
  XkbStateModsDepressed = 1.cint
  XkbStateModsLatched = 2.cint

type
  WlDisplay {.
    importc: "struct wl_display", header: "<wayland-client.h>", incompleteStruct
  .} = object

  WlRegistry {.
    importc: "struct wl_registry", header: "<wayland-client.h>", incompleteStruct
  .} = object

  WlCompositor {.
    importc: "struct wl_compositor",
    header: "<wayland-client-protocol.h>",
    incompleteStruct
  .} = object

  WlSurface {.
    importc: "struct wl_surface",
    header: "<wayland-client-protocol.h>",
    incompleteStruct
  .} = object

  WlBuffer {.
    importc: "struct wl_buffer", header: "<wayland-client-protocol.h>", incompleteStruct
  .} = object

  WlOutput {.
    importc: "struct wl_output", header: "<wayland-client-protocol.h>", incompleteStruct
  .} = object

  WlShm {.
    importc: "struct wl_shm", header: "<wayland-client-protocol.h>", incompleteStruct
  .} = object

  WlShmPool {.
    importc: "struct wl_shm_pool",
    header: "<wayland-client-protocol.h>",
    incompleteStruct
  .} = object

  WlSeat {.
    importc: "struct wl_seat", header: "<wayland-client-protocol.h>", incompleteStruct
  .} = object

  WlPointer {.
    importc: "struct wl_pointer",
    header: "<wayland-client-protocol.h>",
    incompleteStruct
  .} = object

  WlKeyboard {.
    importc: "struct wl_keyboard",
    header: "<wayland-client-protocol.h>",
    incompleteStruct
  .} = object
  WlArray {.importc: "struct wl_array", header: "<wayland-util.h>", incompleteStruct.} = object

  ExtSessionLockManager {.
    importc: "struct ext_session_lock_manager_v1",
    header: "lockme/wayland_shim.h",
    incompleteStruct
  .} = object

  ExtSessionLock {.
    importc: "struct ext_session_lock_v1",
    header: "lockme/wayland_shim.h",
    incompleteStruct
  .} = object

  ExtSessionLockSurface {.
    importc: "struct ext_session_lock_surface_v1",
    header: "lockme/wayland_shim.h",
    incompleteStruct
  .} = object

  WpSinglePixelBufferManager {.
    importc: "struct wp_single_pixel_buffer_manager_v1",
    header: "lockme/wayland_shim.h",
    incompleteStruct
  .} = object

  WpViewporter {.
    importc: "struct wp_viewporter", header: "lockme/wayland_shim.h", incompleteStruct
  .} = object

  WpViewport {.
    importc: "struct wp_viewport", header: "lockme/wayland_shim.h", incompleteStruct
  .} = object

  XkbContext {.
    importc: "struct xkb_context", header: "<xkbcommon/xkbcommon.h>", incompleteStruct
  .} = object

  XkbKeymap {.
    importc: "struct xkb_keymap", header: "<xkbcommon/xkbcommon.h>", incompleteStruct
  .} = object

  XkbState {.
    importc: "struct xkb_state", header: "<xkbcommon/xkbcommon.h>", incompleteStruct
  .} = object

  WlRegistryListener {.bycopy.} = object
    global: proc(
      data: pointer,
      registry: ptr WlRegistry,
      name: uint32,
      iface: cstring,
      version: uint32,
    ) {.cdecl.}
    globalRemove {.importc: "global_remove".}:
      proc(data: pointer, registry: ptr WlRegistry, name: uint32) {.cdecl.}

  WlSeatListener {.bycopy.} = object
    capabilities: proc(data: pointer, seat: ptr WlSeat, capabilities: uint32) {.cdecl.}
    name: proc(data: pointer, seat: ptr WlSeat, name: cstring) {.cdecl.}

  WlPointerListener {.bycopy.} = object
    enter: proc(
      data: pointer,
      pointer: ptr WlPointer,
      serial: uint32,
      surface: ptr WlSurface,
      x, y: int32,
    ) {.cdecl.}
    leave: proc(
      data: pointer, pointer: ptr WlPointer, serial: uint32, surface: ptr WlSurface
    ) {.cdecl.}
    motion:
      proc(data: pointer, pointer: ptr WlPointer, time: uint32, x, y: int32) {.cdecl.}
    button: proc(
      data: pointer, pointer: ptr WlPointer, serial, time, button, state: uint32
    ) {.cdecl.}
    axis: proc(data: pointer, pointer: ptr WlPointer, time, axis: uint32, value: int32) {.
      cdecl
    .}
    frame: proc(data: pointer, pointer: ptr WlPointer) {.cdecl.}
    axisSource {.importc: "axis_source".}:
      proc(data: pointer, pointer: ptr WlPointer, axisSource: uint32) {.cdecl.}
    axisStop {.importc: "axis_stop".}:
      proc(data: pointer, pointer: ptr WlPointer, time, axis: uint32) {.cdecl.}
    axisDiscrete {.importc: "axis_discrete".}: proc(
      data: pointer, pointer: ptr WlPointer, axis: uint32, discrete: int32
    ) {.cdecl.}
    axisValue120 {.importc: "axis_value120".}: proc(
      data: pointer, pointer: ptr WlPointer, axis: uint32, value120: int32
    ) {.cdecl.}
    axisRelativeDirection {.importc: "axis_relative_direction".}:
      proc(data: pointer, pointer: ptr WlPointer, axis, direction: uint32) {.cdecl.}

  WlBufferListener {.bycopy.} = object
    release: proc(data: pointer, buffer: ptr WlBuffer) {.cdecl.}

  WlKeyboardListener {.bycopy.} = object
    keymap: proc(
      data: pointer, keyboard: ptr WlKeyboard, format: uint32, fd: int32, size: uint32
    ) {.cdecl.}
    enter: proc(
      data: pointer,
      keyboard: ptr WlKeyboard,
      serial: uint32,
      surface: ptr WlSurface,
      keys: ptr WlArray,
    ) {.cdecl.}
    leave: proc(
      data: pointer, keyboard: ptr WlKeyboard, serial: uint32, surface: ptr WlSurface
    ) {.cdecl.}
    key: proc(data: pointer, keyboard: ptr WlKeyboard, serial, time, key, state: uint32) {.
      cdecl
    .}
    modifiers: proc(
      data: pointer,
      keyboard: ptr WlKeyboard,
      serial, modsDepressed, modsLatched, modsLocked, group: uint32,
    ) {.cdecl.}
    repeatInfo {.importc: "repeat_info".}:
      proc(data: pointer, keyboard: ptr WlKeyboard, rate, delay: int32) {.cdecl.}

  ExtSessionLockListener {.bycopy.} = object
    locked: proc(data: pointer, lock: ptr ExtSessionLock) {.cdecl.}
    finished: proc(data: pointer, lock: ptr ExtSessionLock) {.cdecl.}

  ExtSessionLockSurfaceListener {.bycopy.} = object
    configure: proc(
      data: pointer, surface: ptr ExtSessionLockSurface, serial, width, height: uint32
    ) {.cdecl.}

  ColorKind = enum
    ckInit
    ckInput
    ckFail

  ColorState = object
    kind: ColorKind
    inputIdx: int

  LockState = enum
    lsInitializing
    lsLocking
    lsLocked
    lsExiting

  MatrixBuffer = object
    buffer: ptr WlBuffer
    data: ptr UncheckedArray[uint32]
    width, height: int
    size: int
    scale: float
    busy: bool

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
    matrixRain: MatrixRain
    matrixGpu: MatrixGpuRenderer
    matrixGpuUnavailable: bool
    matrixCpuFallbackLogged: bool
    matrixBuffers: array[2, MatrixBuffer]
    matrixNextBuffer: int

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
    signalFd: cint
    blankActive: bool
    matrixRenderer: MatrixRenderer
    matrixAtlas: MatrixGlyphAtlas
    matrixClockStart: MonoTime
    matrixTicker: MatrixTicker
    failReturnPending: bool
    failReturnAt: MonoTime
    lastInputAt: MonoTime
    idleBlanked: bool

  Lock = ref LockObj

proc wl_display_connect(
  name: cstring
): ptr WlDisplay {.importc, header: "<wayland-client.h>".}

proc wl_display_disconnect(
  display: ptr WlDisplay
) {.importc, header: "<wayland-client.h>".}

proc wl_display_get_fd(
  display: ptr WlDisplay
): cint {.importc, header: "<wayland-client.h>".}

proc wl_display_get_registry(
  display: ptr WlDisplay
): ptr WlRegistry {.importc, header: "<wayland-client-protocol.h>".}

proc wl_display_roundtrip(
  display: ptr WlDisplay
): cint {.importc, header: "<wayland-client.h>".}

proc wl_display_dispatch_pending(
  display: ptr WlDisplay
): cint {.importc, header: "<wayland-client.h>".}

proc wl_display_prepare_read(
  display: ptr WlDisplay
): cint {.importc, header: "<wayland-client.h>".}

proc wl_display_cancel_read(
  display: ptr WlDisplay
) {.importc, header: "<wayland-client.h>".}

proc wl_display_read_events(
  display: ptr WlDisplay
): cint {.importc, header: "<wayland-client.h>".}

proc wl_display_flush(
  display: ptr WlDisplay
): cint {.importc, header: "<wayland-client.h>".}

proc wl_registry_destroy(
  registry: ptr WlRegistry
) {.importc, header: "<wayland-client-protocol.h>".}

proc wl_registry_add_listener(
  registry: ptr WlRegistry, listener: pointer, data: pointer
): cint {.importc: "lockme_wl_registry_add_listener", header: "lockme/wayland_shim.h".}

proc wl_seat_add_listener(
  seat: ptr WlSeat, listener: pointer, data: pointer
): cint {.importc: "lockme_wl_seat_add_listener", header: "lockme/wayland_shim.h".}

proc wl_pointer_add_listener(
  pointer: ptr WlPointer, listener: pointer, data: pointer
): cint {.importc: "lockme_wl_pointer_add_listener", header: "lockme/wayland_shim.h".}

proc wl_keyboard_add_listener(
  keyboard: ptr WlKeyboard, listener: pointer, data: pointer
): cint {.importc: "lockme_wl_keyboard_add_listener", header: "lockme/wayland_shim.h".}

proc wl_buffer_add_listener(
  buffer: ptr WlBuffer, listener: pointer, data: pointer
): cint {.importc: "lockme_wl_buffer_add_listener", header: "lockme/wayland_shim.h".}

proc ext_session_lock_v1_add_listener(
  lock: ptr ExtSessionLock, listener: pointer, data: pointer
): cint {.
  importc: "lockme_ext_session_lock_v1_add_listener", header: "lockme/wayland_shim.h"
.}

proc ext_session_lock_surface_v1_add_listener(
  surface: ptr ExtSessionLockSurface, listener: pointer, data: pointer
): cint {.
  importc: "lockme_ext_session_lock_surface_v1_add_listener",
  header: "lockme/wayland_shim.h"
.}

proc ifaceNameWlCompositor(): cstring {.
  importc: "lockme_iface_name_wl_compositor", header: "lockme/wayland_shim.h"
.}

proc ifaceNameWlOutput(): cstring {.
  importc: "lockme_iface_name_wl_output", header: "lockme/wayland_shim.h"
.}

proc ifaceNameWlSeat(): cstring {.
  importc: "lockme_iface_name_wl_seat", header: "lockme/wayland_shim.h"
.}

proc ifaceNameWlShm(): cstring {.
  importc: "lockme_iface_name_wl_shm", header: "lockme/wayland_shim.h"
.}

proc ifaceNameLockManager(): cstring {.
  importc: "lockme_iface_name_ext_session_lock_manager_v1",
  header: "lockme/wayland_shim.h"
.}

proc ifaceNameViewporter(): cstring {.
  importc: "lockme_iface_name_wp_viewporter", header: "lockme/wayland_shim.h"
.}

proc ifaceNamePixelManager(): cstring {.
  importc: "lockme_iface_name_wp_single_pixel_buffer_manager_v1",
  header: "lockme/wayland_shim.h"
.}

proc bindWlCompositor(
  registry: ptr WlRegistry, name, version: uint32
): ptr WlCompositor {.
  importc: "lockme_registry_bind_wl_compositor", header: "lockme/wayland_shim.h"
.}

proc bindWlOutput(
  registry: ptr WlRegistry, name, version: uint32
): ptr WlOutput {.
  importc: "lockme_registry_bind_wl_output", header: "lockme/wayland_shim.h"
.}

proc bindWlSeat(
  registry: ptr WlRegistry, name, version: uint32
): ptr WlSeat {.
  importc: "lockme_registry_bind_wl_seat", header: "lockme/wayland_shim.h"
.}

proc bindWlShm(
  registry: ptr WlRegistry, name, version: uint32
): ptr WlShm {.importc: "lockme_registry_bind_wl_shm", header: "lockme/wayland_shim.h".}

proc bindLockManager(
  registry: ptr WlRegistry, name, version: uint32
): ptr ExtSessionLockManager {.
  importc: "lockme_registry_bind_ext_session_lock_manager_v1",
  header: "lockme/wayland_shim.h"
.}

proc bindViewporter(
  registry: ptr WlRegistry, name, version: uint32
): ptr WpViewporter {.
  importc: "lockme_registry_bind_wp_viewporter", header: "lockme/wayland_shim.h"
.}

proc bindPixelManager(
  registry: ptr WlRegistry, name, version: uint32
): ptr WpSinglePixelBufferManager {.
  importc: "lockme_registry_bind_wp_single_pixel_buffer_manager_v1",
  header: "lockme/wayland_shim.h"
.}

proc wlCreateSurface(
  compositor: ptr WlCompositor
): ptr WlSurface {.
  importc: "lockme_wl_compositor_create_surface", header: "lockme/wayland_shim.h"
.}

proc wlCompositorDestroy(
  compositor: ptr WlCompositor
) {.importc: "lockme_wl_compositor_destroy", header: "lockme/wayland_shim.h".}

proc wlSurfaceDestroy(
  surface: ptr WlSurface
) {.importc: "lockme_wl_surface_destroy", header: "lockme/wayland_shim.h".}

proc wlSurfaceAttach(
  surface: ptr WlSurface, buffer: ptr WlBuffer, x, y: int32
) {.importc: "lockme_wl_surface_attach", header: "lockme/wayland_shim.h".}

proc wlSurfaceDamageBuffer(
  surface: ptr WlSurface, x, y, width, height: int32
) {.importc: "lockme_wl_surface_damage_buffer", header: "lockme/wayland_shim.h".}

proc wlSurfaceCommit(
  surface: ptr WlSurface
) {.importc: "lockme_wl_surface_commit", header: "lockme/wayland_shim.h".}

proc wlBufferDestroy(
  buffer: ptr WlBuffer
) {.importc: "lockme_wl_buffer_destroy", header: "lockme/wayland_shim.h".}

proc wlOutputRelease(
  output: ptr WlOutput
) {.importc: "lockme_wl_output_release", header: "lockme/wayland_shim.h".}

proc wlShmCreatePool(
  shm: ptr WlShm, fd, size: int32
): ptr WlShmPool {.
  importc: "lockme_wl_shm_create_pool", header: "lockme/wayland_shim.h"
.}

proc wlShmDestroy(
  shm: ptr WlShm
) {.importc: "lockme_wl_shm_destroy", header: "lockme/wayland_shim.h".}

proc wlShmPoolCreateBuffer(
  pool: ptr WlShmPool, offset, width, height, stride: int32, format: uint32
): ptr WlBuffer {.
  importc: "lockme_wl_shm_pool_create_buffer", header: "lockme/wayland_shim.h"
.}

proc wlShmPoolDestroy(
  pool: ptr WlShmPool
) {.importc: "lockme_wl_shm_pool_destroy", header: "lockme/wayland_shim.h".}

proc wlSeatGetPointer(
  seat: ptr WlSeat
): ptr WlPointer {.
  importc: "lockme_wl_seat_get_pointer", header: "lockme/wayland_shim.h"
.}

proc wlSeatGetKeyboard(
  seat: ptr WlSeat
): ptr WlKeyboard {.
  importc: "lockme_wl_seat_get_keyboard", header: "lockme/wayland_shim.h"
.}

proc wlSeatRelease(
  seat: ptr WlSeat
) {.importc: "lockme_wl_seat_release", header: "lockme/wayland_shim.h".}

proc wlPointerRelease(
  pointer: ptr WlPointer
) {.importc: "lockme_wl_pointer_release", header: "lockme/wayland_shim.h".}

proc wlPointerSetCursor(
  pointer: ptr WlPointer, serial: uint32, surface: ptr WlSurface, x, y: int32
) {.importc: "lockme_wl_pointer_set_cursor", header: "lockme/wayland_shim.h".}

proc wlKeyboardRelease(
  keyboard: ptr WlKeyboard
) {.importc: "lockme_wl_keyboard_release", header: "lockme/wayland_shim.h".}

proc lockManagerLock(
  manager: ptr ExtSessionLockManager
): ptr ExtSessionLock {.
  importc: "lockme_ext_session_lock_manager_v1_lock", header: "lockme/wayland_shim.h"
.}

proc lockManagerDestroy(
  manager: ptr ExtSessionLockManager
) {.
  importc: "lockme_ext_session_lock_manager_v1_destroy", header: "lockme/wayland_shim.h"
.}

proc sessionLockDestroy(
  lock: ptr ExtSessionLock
) {.importc: "lockme_ext_session_lock_v1_destroy", header: "lockme/wayland_shim.h".}

proc sessionLockUnlockAndDestroy(
  lock: ptr ExtSessionLock
) {.
  importc: "lockme_ext_session_lock_v1_unlock_and_destroy",
  header: "lockme/wayland_shim.h"
.}

proc sessionLockGetSurface(
  lock: ptr ExtSessionLock, surface: ptr WlSurface, output: ptr WlOutput
): ptr ExtSessionLockSurface {.
  importc: "lockme_ext_session_lock_v1_get_lock_surface",
  header: "lockme/wayland_shim.h"
.}

proc lockSurfaceDestroy(
  surface: ptr ExtSessionLockSurface
) {.
  importc: "lockme_ext_session_lock_surface_v1_destroy", header: "lockme/wayland_shim.h"
.}

proc lockSurfaceAckConfigure(
  surface: ptr ExtSessionLockSurface, serial: uint32
) {.
  importc: "lockme_ext_session_lock_surface_v1_ack_configure",
  header: "lockme/wayland_shim.h"
.}

proc pixelCreateBuffer(
  manager: ptr WpSinglePixelBufferManager, r, g, b, a: uint32
): ptr WlBuffer {.
  importc: "lockme_wp_single_pixel_buffer_manager_v1_create_u32_rgba_buffer",
  header: "lockme/wayland_shim.h"
.}

proc pixelManagerDestroy(
  manager: ptr WpSinglePixelBufferManager
) {.
  importc: "lockme_wp_single_pixel_buffer_manager_v1_destroy",
  header: "lockme/wayland_shim.h"
.}

proc viewporterGetViewport(
  viewporter: ptr WpViewporter, surface: ptr WlSurface
): ptr WpViewport {.
  importc: "lockme_wp_viewporter_get_viewport", header: "lockme/wayland_shim.h"
.}

proc viewporterDestroy(
  viewporter: ptr WpViewporter
) {.importc: "lockme_wp_viewporter_destroy", header: "lockme/wayland_shim.h".}

proc viewportDestroy(
  viewport: ptr WpViewport
) {.importc: "lockme_wp_viewport_destroy", header: "lockme/wayland_shim.h".}

proc viewportSetDestination(
  viewport: ptr WpViewport, width, height: int32
) {.importc: "lockme_wp_viewport_set_destination", header: "lockme/wayland_shim.h".}

proc xkb_context_new(
  flags: cint
): ptr XkbContext {.importc, header: "<xkbcommon/xkbcommon.h>".}

proc xkb_context_unref(
  context: ptr XkbContext
) {.importc, header: "<xkbcommon/xkbcommon.h>".}

proc xkb_keymap_new_from_buffer(
  context: ptr XkbContext, buffer: cstring, length: csize_t, format, flags: cint
): ptr XkbKeymap {.importc, header: "<xkbcommon/xkbcommon.h>".}

proc xkb_keymap_unref(
  keymap: ptr XkbKeymap
) {.importc, header: "<xkbcommon/xkbcommon.h>".}

proc xkb_state_new(
  keymap: ptr XkbKeymap
): ptr XkbState {.importc, header: "<xkbcommon/xkbcommon.h>".}

proc xkb_state_ref(
  state: ptr XkbState
): ptr XkbState {.importc, header: "<xkbcommon/xkbcommon.h>".}

proc xkb_state_unref(state: ptr XkbState) {.importc, header: "<xkbcommon/xkbcommon.h>".}
proc xkb_state_update_mask(
  state: ptr XkbState,
  depressed, latched, locked, depressedLayout, latchedLayout, lockedLayout: uint32,
): cint {.importc, header: "<xkbcommon/xkbcommon.h>".}

proc xkb_state_key_get_one_sym(
  state: ptr XkbState, keycode: uint32
): uint32 {.importc, header: "<xkbcommon/xkbcommon.h>".}

proc xkb_state_key_get_utf8(
  state: ptr XkbState, keycode: uint32, buffer: cstring, size: csize_t
): cint {.importc, header: "<xkbcommon/xkbcommon.h>".}

proc xkb_state_mod_name_is_active(
  state: ptr XkbState, name: cstring, kind: cint
): cint {.importc, header: "<xkbcommon/xkbcommon.h>".}

proc memfd_create(name: cstring, flags: cuint): cint {.importc, header: "<sys/mman.h>".}
proc signalfd(
  fd: cint, mask: var Sigset, flags: cint
): cint {.importc, header: "<sys/signalfd.h>".}

proc prctl(
  option: cint, arg2, arg3, arg4, arg5: culong
): cint {.importc, header: "<sys/prctl.h>", varargs.}

proc explicit_bzero(p: pointer, n: csize_t) {.importc, header: "<string.h>".}
proc strerror(errnum: cint): cstring {.importc, header: "<string.h>".}
proc mlockall(flags: cint): cint {.importc, header: "<sys/mman.h>".}
proc setrlimit(
  resource: cint, rlim: ptr RLimit
): cint {.importc, header: "<sys/resource.h>".}

proc getrlimit(
  resource: cint, rlim: ptr RLimit
): cint {.importc, header: "<sys/resource.h>".}

const
  PrSetDumpable = 4.cint
  PrSetNoNewPrivs = 38.cint
  MclCurrent = 1.cint
  MclFuture = 2.cint
  RlimitCoreId = 4.cint # Linux: RLIMIT_CORE
  RlimitMemlockId = 8.cint # Linux: RLIMIT_MEMLOCK
  WlShmFormatXrgb8888 = 1'u32

var
  registryListener: WlRegistryListener
  seatListener: WlSeatListener
  pointerListener: WlPointerListener
  bufferListener: WlBufferListener
  keyboardListener: WlKeyboardListener
  sessionLockListener: ExtSessionLockListener
  lockSurfaceListener: ExtSessionLockSurfaceListener

proc fatal(message: string) {.noreturn.} =
  quit("lockme: " & message, 1)

proc logEnabled(lock: Lock, level: LogLevel): bool =
  ord(lock.opts.logLevel) >= ord(level)

proc logMessage(lock: Lock, level: LogLevel, message: string) =
  if lock.logEnabled(level):
    stderr.writeLine("lockme: " & message)

proc logMatrixFailure(output: Output, message: string) =
  let lock = output.lock
  if not lock.blankActive or lock.logEnabled(llWarning):
    stderr.writeLine("lockme: warning: matrix output " & $output.name & ": " & message)

proc matrixSurfaceRenderable(output: Output): bool =
  output.configured and not output.surface.isNil and output.width > 0 and
    output.height > 0

proc rgba16(value: uint32, shift: int): uint32 =
  let component = (value shr shift) and 0xff'u32
  component * (0xffffffff'u32 div 0xff'u32)

proc bufferIndex(lock: Lock, color: ColorState): int =
  ## Buffer layout: [init, fail, input0, input1, ...].
  case color.kind
  of ckInit:
    0
  of ckFail:
    1
  of ckInput:
    2 + color.inputIdx

proc initState(): ColorState =
  ColorState(kind: ckInit, inputIdx: 0)

proc failState(): ColorState =
  ColorState(kind: ckFail, inputIdx: 0)

proc inputState(idx: int): ColorState =
  ColorState(kind: ckInput, inputIdx: idx)

proc nextInputState(lock: Lock): ColorState =
  ## Rotate through the input palette. Wraps after the last entry.
  let n = lock.opts.inputColors.len
  if n <= 0:
    return initState()
  let nextIdx =
    if lock.color.kind == ckInput:
      (lock.color.inputIdx + 1) mod n
    else:
      0
  inputState(nextIdx)

proc wantsMatrix(lock: Lock): bool =
  not lock.blankActive and lock.color.kind == ckInit and lock.password.len == 0

proc destroyMatrixBuffers(output: Output, resetGpuUnavailable = true)

proc sameMatrixScale(a, b: float): bool =
  abs(a - b) < 0.001

proc matrixScaleWidth(lock: Lock): int =
  for output in lock.outputs:
    if output.configured:
      result = max(result, int(output.width))

proc desiredMatrixScale(lock: Lock): float =
  matrixEffectiveScale(lock.opts.matrixCellScale, lock.matrixScaleWidth())

proc ensureMatrixRenderer(lock: Lock): bool =
  let scale = lock.desiredMatrixScale()
  if not lock.matrixRenderer.isNil and sameMatrixScale(lock.matrixRenderer.scale, scale):
    return true
  if not lock.matrixRenderer.isNil:
    for output in lock.outputs:
      output.destroyMatrixBuffers()
    lock.matrixRenderer.close()
    lock.matrixRenderer = nil
    lock.matrixAtlas = MatrixGlyphAtlas()
  lock.matrixRenderer = initMatrixRenderer(scale)
  if lock.matrixRenderer.isNil:
    return false
  lock.matrixAtlas = buildMatrixGlyphAtlas(lock.matrixRenderer)
  true

proc destroyMatrixBuffers(output: Output, resetGpuUnavailable = true) =
  if not output.matrixGpu.isNil:
    output.matrixGpu.close()
    output.matrixGpu = nil
  for buf in mitems(output.matrixBuffers):
    if not buf.data.isNil:
      discard munmap(buf.data, buf.size)
    if not buf.buffer.isNil:
      wlBufferDestroy(buf.buffer)
    buf = MatrixBuffer()
  output.matrixNextBuffer = 0
  if resetGpuUnavailable:
    output.matrixGpuUnavailable = false

proc createMatrixGpu(output: Output): bool =
  let lock = output.lock
  if lock.opts.noGpu or lock.blankActive or not output.matrixSurfaceRenderable():
    return false
  if not lock.ensureMatrixRenderer():
    output.logMatrixFailure("failed to initialize matrix renderer")
    return false
  if output.matrixGpuUnavailable:
    return false
  if output.matrixGpu.isNil:
    output.matrixGpu = initMatrixGpuRenderer(
      cast[pointer](lock.display),
      cast[pointer](output.surface),
      int(output.width),
      int(output.height),
      lock.matrixAtlas,
    )
    if output.matrixGpu.isNil:
      output.logMatrixFailure("GPU renderer unavailable: " & matrixGpuLastError())
      output.matrixGpuUnavailable = true
      return false
  elif not output.matrixGpu.resize(int(output.width), int(output.height)):
    output.logMatrixFailure("GPU renderer resize failed: " & matrixGpuLastError())
    output.matrixGpu.close()
    output.matrixGpu = nil
    return false
  true

proc createMatrixShmBuffers(output: Output, allowGpu = true) =
  let lock = output.lock
  output.destroyMatrixBuffers(resetGpuUnavailable = allowGpu)
  if lock.blankActive or not output.matrixSurfaceRenderable():
    return
  if not lock.ensureMatrixRenderer():
    output.logMatrixFailure("failed to initialize matrix renderer")
    return

  if allowGpu and output.createMatrixGpu():
    return

  if lock.shm.isNil:
    output.logMatrixFailure("wl_shm unavailable for CPU renderer fallback")
    return

  if not output.matrixCpuFallbackLogged:
    output.logMatrixFailure("using CPU renderer fallback")
    output.matrixCpuFallbackLogged = true

  let geometry = matrixRenderGeometry(output.width, output.height, lock.matrixRenderer)
  let cols = geometry.cols
  let rows = geometry.rows
  let bufWidth = geometry.width
  let bufHeight = geometry.height

  if lock.logEnabled(llDebug):
    lock.logMessage(
      llDebug,
      "matrix output " & $output.name & ": surface=" & $output.width & "x" &
        $output.height & " render=" & $bufWidth & "x" & $bufHeight & " cells=" & $cols &
        "x" & $rows & " renderer=cpu-alpha" & " scale=" & $geometry.scale,
    )

  if bufWidth <= 0 or bufHeight <= 0:
    output.logMatrixFailure(
      "surface too small for matrix cells at scale " & $geometry.scale
    )
    return

  let layout = matrixShmBufferLayout(bufWidth, bufHeight)
  if not layout.valid:
    output.logMatrixFailure(
      "render buffer too large: " & $bufWidth & "x" & $bufHeight & " (max " &
        $MatrixShmMaxDimension & "x" & $MatrixShmMaxDimension & ")"
    )
    return
  let size = layout.size
  let stride = layout.stride

  for i in 0 ..< output.matrixBuffers.len:
    let buf = addr output.matrixBuffers[i]
    let fd = memfd_create("lockme-matrix".cstring, 0)
    if fd < 0:
      output.destroyMatrixBuffers()
      output.logMatrixFailure("memfd_create failed")
      return
    if ftruncate(fd, size.Off) != 0:
      discard close(fd)
      output.destroyMatrixBuffers()
      output.logMatrixFailure("ftruncate failed for " & $size & " bytes")
      return

    let mapped = mmap(nil, size, PROT_READ or PROT_WRITE, MAP_SHARED, fd, 0)
    if mapped == cast[pointer](-1):
      discard close(fd)
      output.destroyMatrixBuffers()
      output.logMatrixFailure("mmap failed for " & $size & " bytes")
      return

    let pool = wlShmCreatePool(lock.shm, fd, size.int32)
    discard close(fd)
    if pool.isNil:
      discard munmap(mapped, size)
      output.destroyMatrixBuffers()
      output.logMatrixFailure("wl_shm pool creation failed")
      return

    let wlbuf = wlShmPoolCreateBuffer(
      pool, 0, bufWidth.int32, bufHeight.int32, stride.int32, WlShmFormatXrgb8888
    )
    wlShmPoolDestroy(pool)
    if wlbuf.isNil:
      discard munmap(mapped, size)
      output.destroyMatrixBuffers()
      output.logMatrixFailure("wl_shm buffer creation failed")
      return

    buf[] = MatrixBuffer(
      buffer: wlbuf,
      data: cast[ptr UncheckedArray[uint32]](mapped),
      width: bufWidth,
      height: bufHeight,
      size: size,
      scale: geometry.scale,
      busy: false,
    )
    discard wl_buffer_add_listener(
      buf.buffer, cast[pointer](addr bufferListener), cast[pointer](buf)
    )

  output.matrixRain = initMatrixRain(cols, rows)
  output.matrixNextBuffer = 0
  if lock.logEnabled(llDebug):
    lock.logMessage(
      llDebug,
      "matrix output " & $output.name & ": allocated " & $output.matrixBuffers.len &
        " buffers of " & $size & " bytes",
    )

proc attachBuffer(output: Output, buffer: ptr WlBuffer) =
  if buffer.isNil or not output.configured or output.surface.isNil:
    return
  wlSurfaceAttach(output.surface, buffer, 0, 0)
  wlSurfaceDamageBuffer(output.surface, 0, 0, high(int32), high(int32))
  viewportSetDestination(output.viewport, output.width, output.height)
  wlSurfaceCommit(output.surface)

proc attachColor(output: Output, color: ColorState) =
  let idx = output.lock.bufferIndex(color)
  output.attachBuffer(output.lock.buffers[idx])

proc hasMatrixBuffers(output: Output): bool =
  for buf in output.matrixBuffers:
    if not buf.buffer.isNil and not buf.data.isNil:
      return true
  false

proc matrixNowMs(lock: Lock, now: MonoTime): int64

proc attachMatrixFrame(output: Output): bool =
  if not output.matrixSurfaceRenderable():
    return false
  if output.matrixGpu.isNil and not output.hasMatrixBuffers():
    output.createMatrixShmBuffers()
  if not output.matrixGpu.isNil:
    viewportSetDestination(output.viewport, output.width, output.height)
    if output.matrixGpu.render(
      output.lock.matrixNowMs(getMonoTime()),
      output.lock.opts.matrixFallSpeed,
      output.lock.opts.matrixCycleSpeed,
      output.lock.opts.matrixRaindropLength,
      output.lock.opts.matrixBrightnessDecay,
    ):
      return true
    output.logMatrixFailure(
      "GPU renderer failed during render; using CPU renderer fallback: " &
        matrixGpuLastError()
    )
    output.matrixGpu.close()
    output.matrixGpu = nil
    output.matrixGpuUnavailable = true
    output.createMatrixShmBuffers(allowGpu = false)
    if not output.hasMatrixBuffers():
      return false
  if not output.hasMatrixBuffers():
    return false
  for offset in 0 ..< output.matrixBuffers.len:
    let idx = (output.matrixNextBuffer + offset) mod output.matrixBuffers.len
    if output.matrixBuffers[idx].buffer.isNil or output.matrixBuffers[idx].data.isNil:
      continue
    if output.matrixBuffers[idx].busy:
      continue
    renderMatrix(
      output.matrixRain,
      output.lock.matrixRenderer,
      output.matrixBuffers[idx].data,
      output.matrixBuffers[idx].width,
      output.matrixBuffers[idx].height,
    )
    output.attachBuffer(output.matrixBuffers[idx].buffer)
    output.matrixBuffers[idx].busy = true
    output.matrixNextBuffer = (idx + 1) mod output.matrixBuffers.len
    return true
  true

proc presentOutput(output: Output) =
  if output.lock.wantsMatrix():
    if not output.matrixSurfaceRenderable():
      return
    if output.attachMatrixFrame():
      return
    output.logMatrixFailure("no matrix buffer available; using init color fallback")
  output.attachColor(output.lock.color)

proc setColor(lock: Lock, color: ColorState) =
  if lock.color == color:
    return
  if color.kind != ckFail:
    lock.failReturnPending = false
  lock.color = color
  for output in lock.outputs:
    output.presentOutput()

proc presentAll(lock: Lock) =
  for output in lock.outputs:
    output.presentOutput()

proc toggleBlank(lock: Lock) =
  if lock.state == lsExiting:
    return
  lock.blankActive = not lock.blankActive
  if lock.blankActive:
    for output in lock.outputs:
      output.destroyMatrixBuffers()
  else:
    discard lock.ensureMatrixRenderer()
    for output in lock.outputs:
      if output.configured:
        output.createMatrixShmBuffers()
  lock.presentAll()

proc failReturnTimeout(now, deadline: MonoTime): cint =
  if deadline <= now:
    return 0.cint
  let ms = (deadline - now).inMilliseconds
  if ms > int64(high(cint)):
    high(cint)
  else:
    cint(ms)

proc idleBlankTimeout(opts: Options, lastInputAt, now: MonoTime): cint =
  if opts.idleTimeoutSecs <= 0:
    return -1.cint
  let deadline = lastInputAt + initDuration(seconds = opts.idleTimeoutSecs)
  if deadline <= now:
    return 0.cint
  let ms = (deadline - now).inMilliseconds
  if ms > int64(high(cint)):
    high(cint)
  else:
    cint(ms)

proc matrixNowMs(lock: Lock, now: MonoTime): int64 =
  if lock.matrixClockStart.ticks == 0:
    return 0
  (now - lock.matrixClockStart).inMilliseconds

proc combinePollTimeout(a, b: cint): cint =
  if a < 0:
    b
  elif b < 0:
    a
  elif a < b:
    a
  else:
    b

proc rlimitMemlockSummary(): string =
  var limit: RLimit
  if getrlimit(RlimitMemlockId, addr limit) != 0:
    return "unknown"
  "soft=" & $limit.rlim_cur & " hard=" & $limit.rlim_max & " bytes"

proc mlockallFailureMessage(flags: cint, err: cint): string =
  "mlockall(flags=" & $flags & ") failed: " & $strerror(err) & " (RLIMIT_MEMLOCK " &
    rlimitMemlockSummary() &
    "); transient parent-process password material may be paged to swap, but the dedicated password buffer remains mlock'd"

proc makeSignalFd(): cint =
  var mask: Sigset
  var oldMask: Sigset
  if sigemptyset(mask) != 0:
    return -1
  if sigaddset(mask, SIGINT) != 0 or sigaddset(mask, SIGTERM) != 0:
    return -1
  if sigprocmask(SIG_BLOCK, mask, oldMask) != 0:
    return -1
  result = signalfd(-1, mask, O_CLOEXEC or O_NONBLOCK)
  if result < 0:
    var discardMask: Sigset
    discard sigprocmask(SIG_SETMASK, oldMask, discardMask)
    return -1

proc signalName(signo: uint32): string =
  if signo == uint32(SIGINT):
    "SIGINT"
  elif signo == uint32(SIGTERM):
    "SIGTERM"
  else:
    "signal " & $signo

proc drainSignalFd(lock: Lock): bool =
  var info: array[128, uint8]
  while true:
    let rc = read(lock.signalFd, addr info[0], info.len)
    if rc == info.len:
      result = true
      let signo =
        uint32(info[0]) or (uint32(info[1]) shl 8) or (uint32(info[2]) shl 16) or
        (uint32(info[3]) shl 24)
      lock.logMessage(llDebug, "received " & signalName(signo) & "; exiting")
    elif rc < 0 and errno == EINTR:
      continue
    else:
      break

proc createOutputSurface(output: Output) =
  let lock = output.lock
  output.surface = wlCreateSurface(lock.compositor)
  if output.surface.isNil:
    fatal("failed to create wl_surface")
  output.lockSurface =
    sessionLockGetSurface(lock.sessionLock, output.surface, output.wlOutput)
  if output.lockSurface.isNil:
    fatal("failed to create session lock surface")
  discard ext_session_lock_surface_v1_add_listener(
    output.lockSurface, cast[pointer](addr lockSurfaceListener), cast[pointer](output)
  )
  output.viewport = viewporterGetViewport(lock.viewporter, output.surface)
  if output.viewport.isNil:
    fatal("failed to create viewport")

proc destroyOutput(output: Output) =
  output.destroyMatrixBuffers()
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

proc createSolidPixelBuffer(lock: Lock, rgb: uint32): ptr WlBuffer =
  pixelCreateBuffer(
    lock.pixelManager, rgba16(rgb, 16), rgba16(rgb, 8), rgba16(rgb, 0), 0xffffffff'u32
  )

proc createSolidShmBuffer(lock: Lock, rgb: uint32): ptr WlBuffer =
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

proc createBuffer(lock: Lock, rgb: uint32): ptr WlBuffer =
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

proc registryGlobal(
    data: pointer,
    registry: ptr WlRegistry,
    name: uint32,
    iface: cstring,
    version: uint32,
) {.cdecl.} =
  let lock = cast[Lock](data)
  let ifaceName = $iface

  if ifaceName == $ifaceNameWlCompositor():
    if version < 4:
      fatal("wl_compositor version 4 is required")
    lock.compositor = bindWlCompositor(registry, name, 4)
  elif ifaceName == $ifaceNameWlOutput():
    if version < 3:
      fatal("wl_output version 3 is required")
    let output =
      Output(lock: lock, name: name, wlOutput: bindWlOutput(registry, name, 3))
    lock.outputs.add(output)
    if lock.state in {lsLocking, lsLocked}:
      output.createOutputSurface()
  elif ifaceName == $ifaceNameWlSeat():
    if version < 5:
      fatal("wl_seat version 5 is required")
    let seat = Seat(lock: lock, name: name, wlSeat: bindWlSeat(registry, name, 5))
    lock.seats.add(seat)
    discard wl_seat_add_listener(
      seat.wlSeat, cast[pointer](addr seatListener), cast[pointer](seat)
    )
  elif ifaceName == $ifaceNameWlShm():
    lock.shm = bindWlShm(registry, name, 1)
  elif ifaceName == $ifaceNameLockManager():
    lock.lockManager = bindLockManager(registry, name, 1)
  elif ifaceName == $ifaceNameViewporter():
    lock.viewporter = bindViewporter(registry, name, 1)
  elif ifaceName == $ifaceNamePixelManager():
    lock.pixelManager = bindPixelManager(registry, name, 1)

proc registryGlobalRemove(
    data: pointer, registry: ptr WlRegistry, name: uint32
) {.cdecl.} =
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

proc seatName(data: pointer, seat: ptr WlSeat, name: cstring) {.cdecl.} =
  discard

proc pointerEnter(
    data: pointer,
    pointer: ptr WlPointer,
    serial: uint32,
    surface: ptr WlSurface,
    x, y: int32,
) {.cdecl.} =
  wlPointerSetCursor(pointer, serial, nil, 0, 0)

proc bufferRelease(data: pointer, buffer: ptr WlBuffer) {.cdecl.} =
  let matrixBuffer = cast[ptr MatrixBuffer](data)
  matrixBuffer.busy = false

proc pointerIgnore(data: pointer, pointer: ptr WlPointer) {.cdecl.} =
  discard

proc pointerIgnoreLeave(
    data: pointer, pointer: ptr WlPointer, serial: uint32, surface: ptr WlSurface
) {.cdecl.} =
  discard

proc pointerIgnoreMotion(
    data: pointer, pointer: ptr WlPointer, time: uint32, x, y: int32
) {.cdecl.} =
  discard

proc pointerIgnoreButton(
    data: pointer, pointer: ptr WlPointer, serial, time, button, state: uint32
) {.cdecl.} =
  discard

proc pointerIgnoreAxis(
    data: pointer, pointer: ptr WlPointer, time, axis: uint32, value: int32
) {.cdecl.} =
  discard

proc pointerIgnoreAxisSource(
    data: pointer, pointer: ptr WlPointer, axisSource: uint32
) {.cdecl.} =
  discard

proc pointerIgnoreAxisStop(
    data: pointer, pointer: ptr WlPointer, time, axis: uint32
) {.cdecl.} =
  discard

proc pointerIgnoreAxisDiscrete(
    data: pointer, pointer: ptr WlPointer, axis: uint32, discrete: int32
) {.cdecl.} =
  discard

proc pointerIgnoreAxisValue120(
    data: pointer, pointer: ptr WlPointer, axis: uint32, value120: int32
) {.cdecl.} =
  discard

proc pointerIgnoreAxisRelativeDirection(
    data: pointer, pointer: ptr WlPointer, axis, direction: uint32
) {.cdecl.} =
  discard

const KeymapSizeMax = 1024 * 1024 # 1 MiB sanity cap on compositor-supplied keymap

proc keyboardKeymap(
    data: pointer, keyboard: ptr WlKeyboard, format: uint32, fd: int32, size: uint32
) {.cdecl.} =
  let seat = cast[Seat](data)
  defer:
    discard close(fd)
  if format != uint32(XkbKeymapFormatTextV1):
    return
  if size == 0 or size > uint32(KeymapSizeMax):
    return
  let mapped = mmap(nil, int(size), PROT_READ, MAP_PRIVATE, cint(fd), 0)
  if mapped == cast[pointer](-1):
    return
  defer:
    discard munmap(mapped, int(size))
  # The Wayland protocol guarantees a trailing NUL within the mapped region,
  # so we pass `size - 1` as the length to xkb_keymap_new_from_buffer.
  let length = csize_t(size) - 1
  let keymap = xkb_keymap_new_from_buffer(
    seat.lock.xkbContext, cast[cstring](mapped), length, XkbKeymapFormatTextV1, 0
  )
  if keymap.isNil:
    return
  defer:
    xkb_keymap_unref(keymap)
  let state = xkb_state_new(keymap)
  if state.isNil:
    return
  if not seat.xkbState.isNil:
    xkb_state_unref(seat.xkbState)
  seat.xkbState = xkb_state_ref(state)
  xkb_state_unref(state)

proc keyboardEnter(
    data: pointer,
    keyboard: ptr WlKeyboard,
    serial: uint32,
    surface: ptr WlSurface,
    keys: ptr WlArray,
) {.cdecl.} =
  discard

proc keyboardLeave(
    data: pointer, keyboard: ptr WlKeyboard, serial: uint32, surface: ptr WlSurface
) {.cdecl.} =
  discard

proc keyboardRepeatInfo(
    data: pointer, keyboard: ptr WlKeyboard, rate, delay: int32
) {.cdecl.} =
  discard

proc keyboardModifiers(
    data: pointer,
    keyboard: ptr WlKeyboard,
    serial, modsDepressed, modsLatched, modsLocked, group: uint32,
) {.cdecl.} =
  let seat = cast[Seat](data)
  if not seat.xkbState.isNil:
    discard xkb_state_update_mask(
      seat.xkbState, modsDepressed, modsLatched, modsLocked, 0, 0, group
    )

proc isModifierActive(state: ptr XkbState, name: string): bool =
  xkb_state_mod_name_is_active(
    state, name.cstring, XkbStateModsDepressed or XkbStateModsLatched
  ) == 1

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

proc keyboardKey(
    data: pointer, keyboard: ptr WlKeyboard, serial, time, key, state: uint32
) {.cdecl.} =
  if state != WlKeyboardKeyStatePressed:
    return
  let seat = cast[Seat](data)
  let lock = seat.lock
  if lock.state == lsExiting or seat.xkbState.isNil:
    return

  lock.lastInputAt = getMonoTime()
  if lock.idleBlanked:
    lock.idleBlanked = false
    lock.toggleBlank()
    return

  let keycode = key + 8
  let sym = xkb_state_key_get_one_sym(seat.xkbState, keycode)
  if (sym == XkbKeyB or sym == XkbKeyLowerB) and seat.xkbState.isModifierActive("Mod1"):
    lock.toggleBlank()
    return
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
    if seat.xkbState.isModifierActive("Control"):
      lock.password.clear()
      lock.setColor(initState())
      return
    var buffer: array[64, byte]
    let written = xkb_state_key_get_utf8(
      seat.xkbState, keycode, cast[cstring](addr buffer[0]), csize_t(buffer.len)
    )
    if written > 0 and int(written) < buffer.len:
      if lock.password.appendUtf8(buffer.toOpenArray(0, int(written) - 1)):
        lock.setColor(lock.nextInputState())
    explicit_bzero(addr buffer[0], csize_t(buffer.len))
  else:
    var buffer: array[64, byte]
    let written = xkb_state_key_get_utf8(
      seat.xkbState, keycode, cast[cstring](addr buffer[0]), csize_t(buffer.len)
    )
    if written > 0 and int(written) < buffer.len:
      if lock.password.appendUtf8(buffer.toOpenArray(0, int(written) - 1)):
        lock.setColor(lock.nextInputState())
    explicit_bzero(addr buffer[0], csize_t(buffer.len))

proc seatCapabilities(
    data: pointer, wlSeat: ptr WlSeat, capabilities: uint32
) {.cdecl.} =
  let seat = cast[Seat](data)
  if (capabilities and WlSeatCapabilityPointer) != 0 and seat.pointer.isNil:
    seat.pointer = wlSeatGetPointer(wlSeat)
    discard
      wl_pointer_add_listener(seat.pointer, cast[pointer](addr pointerListener), nil)
  elif (capabilities and WlSeatCapabilityPointer) == 0 and not seat.pointer.isNil:
    wlPointerRelease(seat.pointer)
    seat.pointer = nil

  if (capabilities and WlSeatCapabilityKeyboard) != 0 and seat.keyboard.isNil:
    seat.keyboard = wlSeatGetKeyboard(wlSeat)
    discard wl_keyboard_add_listener(
      seat.keyboard, cast[pointer](addr keyboardListener), cast[pointer](seat)
    )
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

proc sessionLocked(data: pointer, sessionLock: ptr ExtSessionLock) {.cdecl.} =
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
    # Re-apply mlock to the password buffer in the background process
    # and refresh MADV_DONTDUMP for the child. Linux does not inherit
    # memory locks across fork.
    lock.password.protectAfterFork()

proc sessionFinished(data: pointer, sessionLock: ptr ExtSessionLock) {.cdecl.} =
  let lock = cast[Lock](data)
  if lock.state == lsLocking:
    fatal("compositor denied session lock; another locker may already be running")
  lock.state = lsExiting

proc lockSurfaceConfigure(
    data: pointer, surface: ptr ExtSessionLockSurface, serial, width, height: uint32
) {.cdecl.} =
  let output = cast[Output](data)
  output.configured = true
  output.width = int32(min(width, uint32(high(int32))))
  output.height = int32(min(height, uint32(high(int32))))
  lockSurfaceAckConfigure(surface, serial)
  output.createMatrixShmBuffers()
  output.lock.presentAll()

proc flushAndPrepareRead(lock: Lock) =
  while wl_display_prepare_read(lock.display) != 0:
    if wl_display_dispatch_pending(lock.display) < 0:
      fatal("failed to dispatch Wayland events")
  while true:
    let rc = wl_display_flush(lock.display)
    if rc >= 0:
      return
    if errno == EAGAIN:
      var pfd =
        TPollfd(fd: wl_display_get_fd(lock.display), events: POLLOUT, revents: 0)
      discard poll(addr pfd, Tnfds(1), -1)
    else:
      discard wl_display_read_events(lock.display)
      fatal("failed to flush Wayland connection")

proc checkRequired(lock: Lock) =
  if lock.compositor.isNil:
    fatal("wl_compositor not advertised")
  if lock.lockManager.isNil:
    fatal("ext_session_lock_manager_v1 not advertised")
  if lock.viewporter.isNil:
    fatal("wp_viewporter not advertised")
  if lock.pixelManager.isNil and lock.shm.isNil:
    fatal("neither wp_single_pixel_buffer_manager_v1 nor wl_shm is advertised")

proc initListeners() =
  registryListener =
    WlRegistryListener(global: registryGlobal, globalRemove: registryGlobalRemove)
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
    axisRelativeDirection: pointerIgnoreAxisRelativeDirection,
  )
  bufferListener = WlBufferListener(release: bufferRelease)
  keyboardListener = WlKeyboardListener(
    keymap: keyboardKeymap,
    enter: keyboardEnter,
    leave: keyboardLeave,
    key: keyboardKey,
    modifiers: keyboardModifiers,
    repeatInfo: keyboardRepeatInfo,
  )
  sessionLockListener =
    ExtSessionLockListener(locked: sessionLocked, finished: sessionFinished)
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
  if not lock.matrixRenderer.isNil:
    lock.matrixRenderer.close()
  if lock.auth.readFd >= 0:
    discard close(lock.auth.readFd)
    lock.auth.readFd = -1
  if lock.auth.writeFd >= 0:
    discard close(lock.auth.writeFd)
    lock.auth.writeFd = -1
  if lock.signalFd >= 0:
    discard close(lock.signalFd)
    lock.signalFd = -1
  lock.password.clear()

proc connectAndDiscover(opts: Options): Lock =
  result = Lock(
    opts: opts,
    state: lsInitializing,
    color: initState(),
    password: initPasswordBuffer(),
    auth: AuthConnection(readFd: -1, writeFd: -1),
    signalFd: -1,
    blankActive: opts.blank,
  )
  result.matrixClockStart = getMonoTime()
  result.lastInputAt = result.matrixClockStart
  if not result.blankActive:
    discard result.ensureMatrixRenderer()
  result.display = wl_display_connect(nil)
  if result.display.isNil:
    fatal("failed to connect to a Wayland compositor")
  result.xkbContext = xkb_context_new(0)
  if result.xkbContext.isNil:
    fatal("failed to create xkb context")
  result.registry = wl_display_get_registry(result.display)
  discard wl_registry_add_listener(
    result.registry, cast[pointer](addr registryListener), cast[pointer](result)
  )
  if wl_display_roundtrip(result.display) < 0:
    fatal("initial Wayland roundtrip failed")

proc checkProtocols*(opts: Options) =
  initListeners()
  let lock = connectAndDiscover(opts)
  defer:
    lock.deinit()
  lock.checkRequired()
  echo "lockme: required Wayland protocols are available"

proc applyProcessHardening(opts: Options) =
  ## Process-wide hardening applied at startup. Each step is best-effort:
  ## a missing kernel feature must not stop the locker from running.
  ##
  ## - PR_SET_DUMPABLE=0: blocks ptrace and /proc snooping by other
  ##   same-UID processes.
  ## - RLIMIT_CORE=0: suppresses core dumps for the whole process.
  ## - mlockall(2): locks pages into RAM so transient password material
  ##   on the stack or in libc internals cannot be paged to swap. Matrix
  ##   mode avoids MCL_FUTURE to avoid locking unbounded GPU/driver pages.
  discard prctl(PrSetDumpable, 0.culong, 0.culong, 0.culong, 0.culong)
  var rl = RLimit(rlim_cur: 0, rlim_max: 0)
  discard setrlimit(RlimitCoreId, addr rl)
  # mlockall may fail with EPERM under low RLIMIT_MEMLOCK or in
  # containers; the password buffer's own mlock is mandatory and handled
  # separately, so a failure here only weakens defense-in-depth.
  let mlockFlags =
    if not opts.blank:
      MclCurrent
    else:
      MclCurrent or MclFuture
  if mlockall(mlockFlags) != 0:
    if opts.logLevel == llDebug:
      stderr.writeLine("lockme: debug: " & mlockallFailureMessage(mlockFlags, errno))

proc applyParentNoNewPrivs() =
  ## Apply after forkAuthChild(). PAM may need setuid helpers such as
  ## unix_chkpwd; no_new_privs would make those helpers ineffective if
  ## inherited by the auth child.
  discard prctl(PrSetNoNewPrivs, 1.culong, 0.culong, 0.culong, 0.culong)

proc runLock*(opts: Options) =
  applyProcessHardening(opts)
  initListeners()
  let lock = connectAndDiscover(opts)
  defer:
    lock.deinit()
  lock.checkRequired()
  lock.auth = forkAuthChild(opts.logLevel == llDebug)
  lock.signalFd = makeSignalFd()
  if lock.signalFd < 0:
    stderr.writeLine(
      "lockme: warning: failed to create signal fd; SIGINT/SIGTERM may not clean up gracefully"
    )
  applyParentNoNewPrivs()
  lock.createBuffers()
  if not lock.pixelManager.isNil:
    pixelManagerDestroy(lock.pixelManager)
    lock.pixelManager = nil

  lock.sessionLock = lockManagerLock(lock.lockManager)
  if lock.sessionLock.isNil:
    fatal("failed to create session lock")
  discard ext_session_lock_v1_add_listener(
    lock.sessionLock, cast[pointer](addr sessionLockListener), cast[pointer](lock)
  )
  lockManagerDestroy(lock.lockManager)
  lock.lockManager = nil
  lock.state = lsLocking

  for output in lock.outputs:
    output.createOutputSurface()

  var pollfds: array[3, TPollfd]
  while lock.state != lsExiting:
    lock.flushAndPrepareRead()
    pollfds[0] =
      TPollfd(fd: wl_display_get_fd(lock.display), events: POLLIN, revents: 0)
    pollfds[1] = TPollfd(fd: lock.auth.readFd, events: POLLIN, revents: 0)
    var pollLen = 2
    if lock.signalFd >= 0:
      pollfds[2] = TPollfd(fd: lock.signalFd, events: POLLIN, revents: 0)
      pollLen = 3

    let pollStart = getMonoTime()
    let matrixVisible = lock.wantsMatrix()
    var timeout = cint(
      matrixFrameTimeoutMs(
        lock.matrixTicker,
        matrixVisible,
        lock.matrixNowMs(pollStart),
        lock.opts.matrixFrameMs,
      )
    )
    if lock.failReturnPending:
      let failTimeout = failReturnTimeout(pollStart, lock.failReturnAt)
      timeout = combinePollTimeout(timeout, failTimeout)
    if not lock.blankActive and lock.opts.idleTimeoutSecs > 0:
      let idleTimeout = idleBlankTimeout(lock.opts, lock.lastInputAt, pollStart)
      timeout = combinePollTimeout(timeout, idleTimeout)

    let pollRc = poll(addr pollfds[0], Tnfds(pollLen), timeout)
    if pollRc < 0:
      if errno == EINTR:
        wl_display_cancel_read(lock.display)
        continue
      fatal("poll failed")

    if (pollfds[0].revents and POLLIN) != 0:
      if wl_display_read_events(lock.display) < 0:
        fatal("failed to read Wayland events")
      while wl_display_dispatch_pending(lock.display) > 0:
        discard
    else:
      wl_display_cancel_read(lock.display)

    if pollLen > 2 and (pollfds[2].revents and POLLIN) != 0:
      if lock.drainSignalFd():
        lock.state = lsExiting
        continue
    elif pollLen > 2 and (pollfds[2].revents and (POLLHUP or POLLERR or POLLNVAL)) != 0:
      lock.state = lsExiting
      continue

    if (pollfds[1].revents and POLLIN) != 0:
      var ok = false
      if not readAuthResult(lock.auth, ok):
        fatal("failed to read auth result")
      lock.logMessage(
        llDebug, "auth child result: " & (if ok: "success" else: "failure")
      )
      if ok:
        sessionLockUnlockAndDestroy(lock.sessionLock)
        lock.sessionLock = nil
        lock.state = lsExiting
      else:
        lock.failReturnPending = true
        lock.failReturnAt =
          getMonoTime() + initDuration(milliseconds = MatrixFailHoldMs)
        lock.setColor(failState())
    elif (pollfds[1].revents and (POLLHUP or POLLERR or POLLNVAL)) != 0:
      fatal("auth child exited unexpectedly")

    if lock.failReturnPending:
      let now = getMonoTime()
      if lock.failReturnAt <= now:
        lock.failReturnPending = false
        if lock.color.kind == ckFail and lock.password.len == 0:
          lock.setColor(initState())

    if lock.opts.idleTimeoutSecs > 0 and not lock.blankActive:
      let now = getMonoTime()
      if idleBlankTimeout(lock.opts, lock.lastInputAt, now) == 0:
        lock.idleBlanked = true
        lock.toggleBlank()

    let matrixFrameNow = getMonoTime()
    if matrixFrameDue(
      lock.matrixTicker,
      lock.wantsMatrix(),
      lock.matrixNowMs(matrixFrameNow),
      lock.opts.matrixFrameMs,
    ):
      for output in lock.outputs:
        output.matrixRain.advance()
        discard output.attachMatrixFrame()

  if wl_display_roundtrip(lock.display) < 0:
    fatal("final Wayland roundtrip failed")
