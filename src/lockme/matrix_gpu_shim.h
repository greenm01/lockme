#ifndef LOCKME_MATRIX_GPU_SHIM_H
#define LOCKME_MATRIX_GPU_SHIM_H

#include <stdint.h>
#include <wayland-client.h>

struct lockme_matrix_gpu;

struct lockme_matrix_gpu *lockme_matrix_gpu_create(
	struct wl_display *display,
	struct wl_surface *surface,
	int32_t width,
	int32_t height,
	int32_t cell_width,
	int32_t cell_height,
	int32_t glyph_count,
	const uint8_t *atlas_pixels,
	int32_t atlas_width,
	int32_t atlas_height);

int32_t lockme_matrix_gpu_resize(struct lockme_matrix_gpu *gpu, int32_t width, int32_t height);

int32_t lockme_matrix_gpu_render(
	struct lockme_matrix_gpu *gpu,
	double time_seconds,
	float fall_speed,
	float cycle_speed,
	float raindrop_length,
	float brightness_decay);

void lockme_matrix_gpu_destroy(struct lockme_matrix_gpu *gpu);
void lockme_matrix_gpu_shutdown(void);
const char *lockme_matrix_gpu_last_error(void);

#endif
