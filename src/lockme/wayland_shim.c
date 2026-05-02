#include "wayland_shim.h"

const char *lockme_iface_name_wl_compositor(void) { return wl_compositor_interface.name; }
const char *lockme_iface_name_wl_output(void) { return wl_output_interface.name; }
const char *lockme_iface_name_wl_seat(void) { return wl_seat_interface.name; }
const char *lockme_iface_name_wl_shm(void) { return wl_shm_interface.name; }
const char *lockme_iface_name_ext_session_lock_manager_v1(void) { return ext_session_lock_manager_v1_interface.name; }
const char *lockme_iface_name_wp_viewporter(void) { return wp_viewporter_interface.name; }
const char *lockme_iface_name_wp_single_pixel_buffer_manager_v1(void) { return wp_single_pixel_buffer_manager_v1_interface.name; }
const char *lockme_iface_name_xdg_wm_base(void) { return xdg_wm_base_interface.name; }

void *lockme_registry_bind_wl_compositor(struct wl_registry *registry, uint32_t name, uint32_t version) {
	return wl_registry_bind(registry, name, &wl_compositor_interface, version);
}

void *lockme_registry_bind_wl_output(struct wl_registry *registry, uint32_t name, uint32_t version) {
	return wl_registry_bind(registry, name, &wl_output_interface, version);
}

void *lockme_registry_bind_wl_seat(struct wl_registry *registry, uint32_t name, uint32_t version) {
	return wl_registry_bind(registry, name, &wl_seat_interface, version);
}

void *lockme_registry_bind_wl_shm(struct wl_registry *registry, uint32_t name, uint32_t version) {
	return wl_registry_bind(registry, name, &wl_shm_interface, version);
}

void *lockme_registry_bind_ext_session_lock_manager_v1(struct wl_registry *registry, uint32_t name, uint32_t version) {
	return wl_registry_bind(registry, name, &ext_session_lock_manager_v1_interface, version);
}

void *lockme_registry_bind_wp_viewporter(struct wl_registry *registry, uint32_t name, uint32_t version) {
	return wl_registry_bind(registry, name, &wp_viewporter_interface, version);
}

void *lockme_registry_bind_wp_single_pixel_buffer_manager_v1(struct wl_registry *registry, uint32_t name, uint32_t version) {
	return wl_registry_bind(registry, name, &wp_single_pixel_buffer_manager_v1_interface, version);
}

void *lockme_registry_bind_xdg_wm_base(struct wl_registry *registry, uint32_t name, uint32_t version) {
	return wl_registry_bind(registry, name, &xdg_wm_base_interface, version);
}

int lockme_wl_registry_add_listener(struct wl_registry *registry, const void *listener, void *data) {
	return wl_registry_add_listener(registry, (const struct wl_registry_listener *) listener, data);
}

int lockme_wl_seat_add_listener(struct wl_seat *seat, const void *listener, void *data) {
	return wl_seat_add_listener(seat, (const struct wl_seat_listener *) listener, data);
}

int lockme_wl_pointer_add_listener(struct wl_pointer *pointer, const void *listener, void *data) {
	return wl_pointer_add_listener(pointer, (const struct wl_pointer_listener *) listener, data);
}

int lockme_wl_keyboard_add_listener(struct wl_keyboard *keyboard, const void *listener, void *data) {
	return wl_keyboard_add_listener(keyboard, (const struct wl_keyboard_listener *) listener, data);
}

int lockme_wl_buffer_add_listener(struct wl_buffer *buffer, const void *listener, void *data) {
	return wl_buffer_add_listener(buffer, (const struct wl_buffer_listener *) listener, data);
}

int lockme_ext_session_lock_v1_add_listener(struct ext_session_lock_v1 *lock, const void *listener, void *data) {
	return ext_session_lock_v1_add_listener(lock, (const struct ext_session_lock_v1_listener *) listener, data);
}

int lockme_ext_session_lock_surface_v1_add_listener(struct ext_session_lock_surface_v1 *surface, const void *listener, void *data) {
	return ext_session_lock_surface_v1_add_listener(surface, (const struct ext_session_lock_surface_v1_listener *) listener, data);
}

int lockme_xdg_wm_base_add_listener(struct xdg_wm_base *wm_base, const void *listener, void *data) {
	return xdg_wm_base_add_listener(wm_base, (const struct xdg_wm_base_listener *) listener, data);
}

int lockme_xdg_surface_add_listener(struct xdg_surface *surface, const void *listener, void *data) {
	return xdg_surface_add_listener(surface, (const struct xdg_surface_listener *) listener, data);
}

int lockme_xdg_toplevel_add_listener(struct xdg_toplevel *toplevel, const void *listener, void *data) {
	return xdg_toplevel_add_listener(toplevel, (const struct xdg_toplevel_listener *) listener, data);
}

struct wl_surface *lockme_wl_compositor_create_surface(struct wl_compositor *compositor) {
	return wl_compositor_create_surface(compositor);
}

void lockme_wl_compositor_destroy(struct wl_compositor *compositor) { wl_compositor_destroy(compositor); }
void lockme_wl_surface_destroy(struct wl_surface *surface) { wl_surface_destroy(surface); }
void lockme_wl_surface_attach(struct wl_surface *surface, struct wl_buffer *buffer, int32_t x, int32_t y) { wl_surface_attach(surface, buffer, x, y); }
void lockme_wl_surface_damage_buffer(struct wl_surface *surface, int32_t x, int32_t y, int32_t width, int32_t height) { wl_surface_damage_buffer(surface, x, y, width, height); }
void lockme_wl_surface_commit(struct wl_surface *surface) { wl_surface_commit(surface); }
void lockme_wl_buffer_destroy(struct wl_buffer *buffer) { wl_buffer_destroy(buffer); }
void lockme_wl_output_release(struct wl_output *output) { wl_output_release(output); }
struct wl_shm_pool *lockme_wl_shm_create_pool(struct wl_shm *shm, int32_t fd, int32_t size) { return wl_shm_create_pool(shm, fd, size); }
void lockme_wl_shm_destroy(struct wl_shm *shm) { wl_shm_destroy(shm); }
struct wl_buffer *lockme_wl_shm_pool_create_buffer(struct wl_shm_pool *pool, int32_t offset, int32_t width, int32_t height, int32_t stride, uint32_t format) {
	return wl_shm_pool_create_buffer(pool, offset, width, height, stride, format);
}
void lockme_wl_shm_pool_destroy(struct wl_shm_pool *pool) { wl_shm_pool_destroy(pool); }

struct wl_pointer *lockme_wl_seat_get_pointer(struct wl_seat *seat) { return wl_seat_get_pointer(seat); }
struct wl_keyboard *lockme_wl_seat_get_keyboard(struct wl_seat *seat) { return wl_seat_get_keyboard(seat); }
void lockme_wl_seat_release(struct wl_seat *seat) { wl_seat_release(seat); }
void lockme_wl_pointer_release(struct wl_pointer *pointer) { wl_pointer_release(pointer); }
void lockme_wl_pointer_set_cursor(struct wl_pointer *pointer, uint32_t serial, struct wl_surface *surface, int32_t hotspot_x, int32_t hotspot_y) {
	wl_pointer_set_cursor(pointer, serial, surface, hotspot_x, hotspot_y);
}
void lockme_wl_keyboard_release(struct wl_keyboard *keyboard) { wl_keyboard_release(keyboard); }

struct ext_session_lock_v1 *lockme_ext_session_lock_manager_v1_lock(struct ext_session_lock_manager_v1 *manager) {
	return ext_session_lock_manager_v1_lock(manager);
}

void lockme_ext_session_lock_manager_v1_destroy(struct ext_session_lock_manager_v1 *manager) { ext_session_lock_manager_v1_destroy(manager); }
void lockme_ext_session_lock_v1_destroy(struct ext_session_lock_v1 *lock) { ext_session_lock_v1_destroy(lock); }
void lockme_ext_session_lock_v1_unlock_and_destroy(struct ext_session_lock_v1 *lock) { ext_session_lock_v1_unlock_and_destroy(lock); }

struct ext_session_lock_surface_v1 *lockme_ext_session_lock_v1_get_lock_surface(struct ext_session_lock_v1 *lock, struct wl_surface *surface, struct wl_output *output) {
	return ext_session_lock_v1_get_lock_surface(lock, surface, output);
}

void lockme_ext_session_lock_surface_v1_destroy(struct ext_session_lock_surface_v1 *surface) { ext_session_lock_surface_v1_destroy(surface); }
void lockme_ext_session_lock_surface_v1_ack_configure(struct ext_session_lock_surface_v1 *surface, uint32_t serial) { ext_session_lock_surface_v1_ack_configure(surface, serial); }

struct wl_buffer *lockme_wp_single_pixel_buffer_manager_v1_create_u32_rgba_buffer(struct wp_single_pixel_buffer_manager_v1 *manager, uint32_t r, uint32_t g, uint32_t b, uint32_t a) {
	return wp_single_pixel_buffer_manager_v1_create_u32_rgba_buffer(manager, r, g, b, a);
}

void lockme_wp_single_pixel_buffer_manager_v1_destroy(struct wp_single_pixel_buffer_manager_v1 *manager) { wp_single_pixel_buffer_manager_v1_destroy(manager); }
struct wp_viewport *lockme_wp_viewporter_get_viewport(struct wp_viewporter *viewporter, struct wl_surface *surface) { return wp_viewporter_get_viewport(viewporter, surface); }
void lockme_wp_viewporter_destroy(struct wp_viewporter *viewporter) { wp_viewporter_destroy(viewporter); }
void lockme_wp_viewport_destroy(struct wp_viewport *viewport) { wp_viewport_destroy(viewport); }
void lockme_wp_viewport_set_destination(struct wp_viewport *viewport, int32_t width, int32_t height) { wp_viewport_set_destination(viewport, width, height); }

void lockme_xdg_wm_base_destroy(struct xdg_wm_base *wm_base) { xdg_wm_base_destroy(wm_base); }
void lockme_xdg_wm_base_pong(struct xdg_wm_base *wm_base, uint32_t serial) { xdg_wm_base_pong(wm_base, serial); }
struct xdg_surface *lockme_xdg_wm_base_get_xdg_surface(struct xdg_wm_base *wm_base, struct wl_surface *surface) { return xdg_wm_base_get_xdg_surface(wm_base, surface); }
void lockme_xdg_surface_destroy(struct xdg_surface *surface) { xdg_surface_destroy(surface); }
void lockme_xdg_surface_ack_configure(struct xdg_surface *surface, uint32_t serial) { xdg_surface_ack_configure(surface, serial); }
void lockme_xdg_surface_set_window_geometry(struct xdg_surface *surface, int32_t x, int32_t y, int32_t width, int32_t height) {
	xdg_surface_set_window_geometry(surface, x, y, width, height);
}
struct xdg_toplevel *lockme_xdg_surface_get_toplevel(struct xdg_surface *surface) { return xdg_surface_get_toplevel(surface); }
void lockme_xdg_toplevel_destroy(struct xdg_toplevel *toplevel) { xdg_toplevel_destroy(toplevel); }
void lockme_xdg_toplevel_set_title(struct xdg_toplevel *toplevel, const char *title) { xdg_toplevel_set_title(toplevel, title); }
void lockme_xdg_toplevel_set_app_id(struct xdg_toplevel *toplevel, const char *app_id) { xdg_toplevel_set_app_id(toplevel, app_id); }
void lockme_xdg_toplevel_set_min_size(struct xdg_toplevel *toplevel, int32_t width, int32_t height) {
	xdg_toplevel_set_min_size(toplevel, width, height);
}
