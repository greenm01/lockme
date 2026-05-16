#include "matrix_gpu_shim.h"

#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-egl.h>

#define SOKOL_IMPL
#define SOKOL_GLES3
#include "vendor/sokol_gfx.h"

/*
 * The rain/symbol state pipeline adapts the classic shader structure from
 * Rezmason/matrix (MIT, copyright 2018 Rezmason): update raindrop state,
 * update symbol state, then render glyphs from an atlas.
 */

typedef struct {
	sg_image image;
	sg_view texture_view;
	sg_view attachment_view;
} lockme_state_target;

struct lockme_matrix_gpu {
	struct wl_egl_window *window;
	EGLSurface surface;
	int32_t width;
	int32_t height;
	int32_t cell_width;
	int32_t cell_height;
	int32_t glyph_count;
	int32_t grid_width;
	int32_t grid_height;
	uint32_t frame_count;
	int current_raindrop;
	int current_symbol;
	lockme_state_target raindrop[2];
	lockme_state_target symbol[2];
};

typedef struct {
	float grid_time[4];
	float timing[4];
} lockme_state_params;

typedef struct {
	float surface_cell[4];
	float atlas_time[4];
	float grid_params[4];
} lockme_final_params;

static EGLDisplay g_display = EGL_NO_DISPLAY;
static EGLConfig g_config = NULL;
static EGLContext g_context = EGL_NO_CONTEXT;
static int g_ref_count = 0;
static bool g_sokol_ready = false;
static sg_pipeline g_raindrop_pipeline;
static sg_shader g_raindrop_shader;
static sg_pipeline g_symbol_pipeline;
static sg_shader g_symbol_shader;
static sg_pipeline g_final_pipeline;
static sg_shader g_final_shader;
static sg_image g_atlas_image;
static sg_view g_atlas_view;
static sg_sampler g_atlas_sampler;
static sg_sampler g_state_sampler;
static int32_t g_atlas_width = 0;
static int32_t g_atlas_height = 0;
static int32_t g_atlas_glyph_count = 0;
static char g_last_error[256];

static const char *fullscreen_vertex_source =
	"#version 300 es\n"
	"out vec2 uv;\n"
	"void main() {\n"
	"  vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));\n"
	"  uv = p;\n"
	"  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);\n"
	"}\n";

static const char *raindrop_fragment_source =
	"#version 300 es\n"
	"precision highp float;\n"
	"in vec2 uv;\n"
	"out vec4 frag_color;\n"
	"uniform vec4 grid_time;\n"
	"uniform vec4 timing;\n"
	"uniform sampler2D previous_raindrop;\n"
	"const float PI = 3.14159265359;\n"
	"const float SQRT_2 = 1.4142135623730951;\n"
	"const float SQRT_5 = 2.23606797749979;\n"
	"float randomFloat(vec2 p) {\n"
	"  float dt = dot(p, vec2(12.9898, 78.233));\n"
	"  return fract(sin(mod(dt, PI)) * 43758.5453123);\n"
	"}\n"
	"float wobble(float x) {\n"
	"  return x + 0.3 * sin(SQRT_2 * x) + 0.2 * sin(SQRT_5 * x);\n"
	"}\n"
	"float rainBrightness(float t, vec2 cell) {\n"
	"  float fall_speed = max(timing.x, 0.001);\n"
	"  float raindrop_length = max(timing.z, 0.05);\n"
	"  float column_time_offset = randomFloat(vec2(cell.x, 0.0)) * 1000.0;\n"
	"  float column_speed_offset = randomFloat(vec2(cell.x + 0.1, 0.0)) * 0.5 + 0.5;\n"
	"  float column_time = column_time_offset + t * fall_speed * column_speed_offset;\n"
	"  float glyph_y = max(grid_time.y, 1.0) - cell.y - 1.0;\n"
	"  float rain_time = (glyph_y * 0.01 + column_time) / raindrop_length;\n"
	"  rain_time = wobble(rain_time);\n"
	"  return 1.0 - fract(rain_time);\n"
	"}\n"
	"void main() {\n"
	"  vec2 grid = max(grid_time.xy, vec2(1.0));\n"
	"  float t = grid_time.z;\n"
	"  float frame = grid_time.w;\n"
	"  vec2 cell = vec2(floor(gl_FragCoord.x), grid.y - floor(gl_FragCoord.y) - 1.0);\n"
	"  vec2 prev_uv = gl_FragCoord.xy / grid;\n"
	"  vec4 prev = texture(previous_raindrop, prev_uv);\n"
	"  float brightness = rainBrightness(t, cell);\n"
	"  float brightness_below = rainBrightness(t, cell + vec2(0.0, 1.0));\n"
	"  float cursor = (brightness > brightness_below) ? 1.0 : 0.0;\n"
	"  if (frame > 0.5) {\n"
	"    brightness = mix(prev.r, brightness, clamp(timing.w, 0.0, 1.0));\n"
	"  }\n"
	"  frag_color = vec4(clamp(brightness, 0.0, 1.0), cursor, 1.0, 1.0);\n"
	"}\n";

static const char *symbol_fragment_source =
	"#version 300 es\n"
	"precision highp float;\n"
	"in vec2 uv;\n"
	"out vec4 frag_color;\n"
	"uniform vec4 grid_time;\n"
	"uniform vec4 timing;\n"
	"uniform sampler2D previous_symbol;\n"
	"uniform sampler2D raindrop_state;\n"
	"const float PI = 3.14159265359;\n"
	"float randomFloat(vec2 p) {\n"
	"  float dt = dot(p, vec2(12.9898, 78.233));\n"
	"  return fract(sin(mod(dt, PI)) * 43758.5453123);\n"
	"}\n"
	"void main() {\n"
	"  vec2 grid = max(grid_time.xy, vec2(1.0));\n"
	"  float time = grid_time.z;\n"
	"  float frame = grid_time.w;\n"
	"  float glyph_count = max(timing.w, 1.0);\n"
	"  vec2 cell = vec2(floor(gl_FragCoord.x), grid.y - floor(gl_FragCoord.y) - 1.0);\n"
	"  vec2 state_uv = gl_FragCoord.xy / grid;\n"
	"  vec4 prev = texture(previous_symbol, state_uv);\n"
	"  float age = prev.g;\n"
	"  float symbol = floor(clamp(prev.r, 0.0, 0.99999) * glyph_count);\n"
	"  if (frame <= 0.5) {\n"
	"    age = randomFloat(state_uv + vec2(0.5));\n"
	"    symbol = floor(glyph_count * randomFloat(state_uv));\n"
	"  }\n"
	"  float cycle_rate = max(timing.y, 0.001);\n"
	"  age += cycle_rate;\n"
	"  if (age >= 1.0) {\n"
	"    symbol = floor(glyph_count * randomFloat(state_uv + vec2(time)));\n"
	"    age = fract(age);\n"
	"  }\n"
	"  frag_color = vec4((symbol + 0.5) / glyph_count, age, 0.0, 1.0);\n"
	"}\n";

static const char *final_fragment_source =
	"#version 300 es\n"
	"precision highp float;\n"
	"in vec2 uv;\n"
	"out vec4 frag_color;\n"
	"uniform vec4 surface_cell;\n"
	"uniform vec4 atlas_time;\n"
	"uniform vec4 grid_params;\n"
	"uniform sampler2D raindrop_state;\n"
	"uniform sampler2D symbol_state;\n"
	"uniform sampler2D glyph_tex;\n"
	"void main() {\n"
	"  float surface_w = surface_cell.x;\n"
	"  float surface_h = surface_cell.y;\n"
	"  float cell_w = max(surface_cell.z, 1.0);\n"
	"  float cell_h = max(surface_cell.w, 1.0);\n"
	"  float glyph_count = max(atlas_time.z, 1.0);\n"
	"  vec2 grid = max(grid_params.xy, vec2(1.0));\n"
	"  vec2 top_pixel = vec2(gl_FragCoord.x, surface_h - gl_FragCoord.y);\n"
	"  if (top_pixel.x < 0.0 || top_pixel.y < 0.0 || top_pixel.x >= surface_w || top_pixel.y >= surface_h) { discard; }\n"
	"  vec2 cell = floor(top_pixel / vec2(cell_w, cell_h));\n"
	"  if (cell.x < 0.0 || cell.y < 0.0 || cell.x >= grid.x || cell.y >= grid.y) { discard; }\n"
	"  vec2 local = fract(top_pixel / vec2(cell_w, cell_h));\n"
	"  vec2 state_uv = vec2((cell.x + 0.5) / grid.x, 1.0 - ((cell.y + 0.5) / grid.y));\n"
	"  vec4 rain = texture(raindrop_state, state_uv);\n"
	"  vec4 symbol_sample = texture(symbol_state, state_uv);\n"
	"  float symbol = clamp(floor(clamp(symbol_sample.r, 0.0, 0.99999) * glyph_count), 0.0, glyph_count - 1.0);\n"
	"  vec2 atlas_size = max(atlas_time.xy, vec2(1.0));\n"
	"  vec2 glyph_size = max(vec2(atlas_size.x / glyph_count, atlas_size.y), vec2(1.0));\n"
	"  vec2 glyph_texel = clamp(local * glyph_size, vec2(0.5), glyph_size - vec2(0.5));\n"
	"  vec2 glyph_uv = vec2((symbol * glyph_size.x + glyph_texel.x) / atlas_size.x, glyph_texel.y / atlas_size.y);\n"
	"  float alpha = texture(glyph_tex, glyph_uv).r;\n"
	"  float brightness = rain.r * 1.1 - 0.5;\n"
	"  if (brightness <= 0.0 || alpha <= 0.01) { discard; }\n"
	"  vec3 trail = vec3(0.0, 0.82, 0.04) * brightness;\n"
	"  vec3 cursor = vec3(0.86, 1.0, 0.86) * max(brightness, 0.55);\n"
	"  vec3 color = mix(trail, cursor, step(0.5, rain.g));\n"
	"  frag_color = vec4(color * alpha, 1.0);\n"
	"}\n";

static void set_error(const char *message) {
	snprintf(g_last_error, sizeof(g_last_error), "%s", message);
}

static int32_t forced_render_fail_after(void) {
	const char *raw = getenv("LOCKME_MATRIX_GPU_FAIL_AFTER");
	if (!raw || raw[0] == '\0') {
		return -1;
	}
	char *end = NULL;
	long value = strtol(raw, &end, 10);
	if (end == raw || *end != '\0' || value < 0) {
		return -1;
	}
	if (value > INT32_MAX) {
		return INT32_MAX;
	}
	return (int32_t)value;
}

static void sokol_logger(const char *tag, uint32_t level, uint32_t item, const char *message, uint32_t line, const char *filename, void *user_data) {
	(void)tag;
	(void)level;
	(void)item;
	(void)filename;
	(void)user_data;
	if (message) {
		snprintf(g_last_error, sizeof(g_last_error), "sokol:%u: %s", line, message);
	}
}

static bool resource_valid(void) {
	if (sg_query_shader_state(g_raindrop_shader) != SG_RESOURCESTATE_VALID) {
		set_error("matrix raindrop shader failed");
		return false;
	}
	if (sg_query_shader_state(g_symbol_shader) != SG_RESOURCESTATE_VALID) {
		set_error("matrix symbol shader failed");
		return false;
	}
	if (sg_query_shader_state(g_final_shader) != SG_RESOURCESTATE_VALID) {
		set_error("matrix final shader failed");
		return false;
	}
	if (sg_query_pipeline_state(g_raindrop_pipeline) != SG_RESOURCESTATE_VALID) {
		set_error("matrix raindrop pipeline failed");
		return false;
	}
	if (sg_query_pipeline_state(g_symbol_pipeline) != SG_RESOURCESTATE_VALID) {
		set_error("matrix symbol pipeline failed");
		return false;
	}
	if (sg_query_pipeline_state(g_final_pipeline) != SG_RESOURCESTATE_VALID) {
		set_error("matrix final pipeline failed");
		return false;
	}
	return true;
}

static void destroy_global_resources(void) {
	if (g_raindrop_pipeline.id != SG_INVALID_ID) {
		sg_destroy_pipeline(g_raindrop_pipeline);
		g_raindrop_pipeline = (sg_pipeline){0};
	}
	if (g_symbol_pipeline.id != SG_INVALID_ID) {
		sg_destroy_pipeline(g_symbol_pipeline);
		g_symbol_pipeline = (sg_pipeline){0};
	}
	if (g_final_pipeline.id != SG_INVALID_ID) {
		sg_destroy_pipeline(g_final_pipeline);
		g_final_pipeline = (sg_pipeline){0};
	}
	if (g_raindrop_shader.id != SG_INVALID_ID) {
		sg_destroy_shader(g_raindrop_shader);
		g_raindrop_shader = (sg_shader){0};
	}
	if (g_symbol_shader.id != SG_INVALID_ID) {
		sg_destroy_shader(g_symbol_shader);
		g_symbol_shader = (sg_shader){0};
	}
	if (g_final_shader.id != SG_INVALID_ID) {
		sg_destroy_shader(g_final_shader);
		g_final_shader = (sg_shader){0};
	}
	if (g_atlas_view.id != SG_INVALID_ID) {
		sg_destroy_view(g_atlas_view);
		g_atlas_view = (sg_view){0};
	}
	if (g_atlas_image.id != SG_INVALID_ID) {
		sg_destroy_image(g_atlas_image);
		g_atlas_image = (sg_image){0};
	}
	if (g_atlas_sampler.id != SG_INVALID_ID) {
		sg_destroy_sampler(g_atlas_sampler);
		g_atlas_sampler = (sg_sampler){0};
	}
	if (g_state_sampler.id != SG_INVALID_ID) {
		sg_destroy_sampler(g_state_sampler);
		g_state_sampler = (sg_sampler){0};
	}
}

static void destroy_state_target(lockme_state_target *target) {
	if (target->attachment_view.id != SG_INVALID_ID) {
		sg_destroy_view(target->attachment_view);
	}
	if (target->texture_view.id != SG_INVALID_ID) {
		sg_destroy_view(target->texture_view);
	}
	if (target->image.id != SG_INVALID_ID) {
		sg_destroy_image(target->image);
	}
	*target = (lockme_state_target){0};
}

static void destroy_state(struct lockme_matrix_gpu *gpu) {
	for (int i = 0; i < 2; i++) {
		destroy_state_target(&gpu->raindrop[i]);
		destroy_state_target(&gpu->symbol[i]);
	}
	gpu->grid_width = 0;
	gpu->grid_height = 0;
	gpu->frame_count = 0;
	gpu->current_raindrop = 0;
	gpu->current_symbol = 0;
}

static lockme_state_target make_state_target(int32_t width, int32_t height, const char *label) {
	lockme_state_target target = {0};
	target.image = sg_make_image(&(sg_image_desc){
		.usage = {
			.color_attachment = true,
			.immutable = true,
		},
		.width = width,
		.height = height,
		.pixel_format = SG_PIXELFORMAT_RGBA8,
		.sample_count = 1,
		.label = label,
	});
	target.texture_view = sg_make_view(&(sg_view_desc){
		.texture = {
			.image = target.image,
		},
		.label = "matrix-state-texture-view",
	});
	target.attachment_view = sg_make_view(&(sg_view_desc){
		.color_attachment = {
			.image = target.image,
		},
		.label = "matrix-state-attachment-view",
	});
	return target;
}

static bool state_target_valid(const lockme_state_target *target) {
	return sg_query_image_state(target->image) == SG_RESOURCESTATE_VALID &&
		sg_query_view_state(target->texture_view) == SG_RESOURCESTATE_VALID &&
		sg_query_view_state(target->attachment_view) == SG_RESOURCESTATE_VALID;
}

static void clear_state_target(lockme_state_target *target) {
	sg_begin_pass(&(sg_pass){
		.action = {
			.colors = {
				[0] = {
					.load_action = SG_LOADACTION_CLEAR,
					.clear_value = { 0.0f, 0.0f, 0.0f, 1.0f },
				},
			},
		},
		.attachments = {
			.colors = { [0] = target->attachment_view },
		},
		.label = "matrix-clear-state-pass",
	});
	sg_end_pass();
}

static bool ensure_state(struct lockme_matrix_gpu *gpu) {
	int32_t grid_width = gpu->width / gpu->cell_width;
	int32_t grid_height = gpu->height / gpu->cell_height;
	if (grid_width < 1) {
		grid_width = 1;
	}
	if (grid_height < 1) {
		grid_height = 1;
	}
	if (gpu->grid_width == grid_width && gpu->grid_height == grid_height) {
		return true;
	}

	destroy_state(gpu);
	gpu->grid_width = grid_width;
	gpu->grid_height = grid_height;
	gpu->raindrop[0] = make_state_target(grid_width, grid_height, "matrix-raindrop-a");
	gpu->raindrop[1] = make_state_target(grid_width, grid_height, "matrix-raindrop-b");
	gpu->symbol[0] = make_state_target(grid_width, grid_height, "matrix-symbol-a");
	gpu->symbol[1] = make_state_target(grid_width, grid_height, "matrix-symbol-b");
	for (int i = 0; i < 2; i++) {
		if (!state_target_valid(&gpu->raindrop[i]) || !state_target_valid(&gpu->symbol[i])) {
			set_error("matrix state target creation failed");
			destroy_state(gpu);
			return false;
		}
		clear_state_target(&gpu->raindrop[i]);
		clear_state_target(&gpu->symbol[i]);
	}
	gpu->frame_count = 0;
	gpu->current_raindrop = 0;
	gpu->current_symbol = 0;
	return true;
}

static bool init_egl(struct wl_display *display) {
	if (g_display != EGL_NO_DISPLAY) {
		return true;
	}

	g_display = eglGetDisplay((EGLNativeDisplayType)display);
	if (g_display == EGL_NO_DISPLAY) {
		set_error("eglGetDisplay failed");
		return false;
	}
	if (!eglInitialize(g_display, NULL, NULL)) {
		set_error("eglInitialize failed");
		g_display = EGL_NO_DISPLAY;
		return false;
	}

	const EGLint attrs[] = {
		EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
		EGL_RED_SIZE, 8,
		EGL_GREEN_SIZE, 8,
		EGL_BLUE_SIZE, 8,
		EGL_ALPHA_SIZE, 8,
		EGL_NONE
	};
	EGLint count = 0;
	if (!eglChooseConfig(g_display, attrs, &g_config, 1, &count) || count < 1) {
		set_error("eglChooseConfig failed");
		eglTerminate(g_display);
		g_display = EGL_NO_DISPLAY;
		return false;
	}

	if (!eglBindAPI(EGL_OPENGL_ES_API)) {
		set_error("eglBindAPI failed");
		eglTerminate(g_display);
		g_display = EGL_NO_DISPLAY;
		return false;
	}

	const EGLint ctx_attrs[] = {
		EGL_CONTEXT_CLIENT_VERSION, 3,
		EGL_NONE
	};
	g_context = eglCreateContext(g_display, g_config, EGL_NO_CONTEXT, ctx_attrs);
	if (g_context == EGL_NO_CONTEXT) {
		set_error("eglCreateContext failed");
		eglTerminate(g_display);
		g_display = EGL_NO_DISPLAY;
		return false;
	}

	return true;
}

static bool make_current(struct lockme_matrix_gpu *gpu) {
	if (!eglMakeCurrent(g_display, gpu->surface, gpu->surface, g_context)) {
		set_error("eglMakeCurrent failed");
		return false;
	}
	return true;
}

static sg_shader_desc raindrop_shader_desc(void) {
	sg_shader_desc desc = {0};
	desc.vertex_func.source = fullscreen_vertex_source;
	desc.fragment_func.source = raindrop_fragment_source;
	desc.uniform_blocks[0].stage = SG_SHADERSTAGE_FRAGMENT;
	desc.uniform_blocks[0].size = sizeof(lockme_state_params);
	desc.uniform_blocks[0].layout = SG_UNIFORMLAYOUT_STD140;
	desc.uniform_blocks[0].glsl_uniforms[0] = (sg_glsl_shader_uniform){ .type = SG_UNIFORMTYPE_FLOAT4, .array_count = 1, .glsl_name = "grid_time" };
	desc.uniform_blocks[0].glsl_uniforms[1] = (sg_glsl_shader_uniform){ .type = SG_UNIFORMTYPE_FLOAT4, .array_count = 1, .glsl_name = "timing" };
	desc.views[0].texture.stage = SG_SHADERSTAGE_FRAGMENT;
	desc.views[0].texture.image_type = SG_IMAGETYPE_2D;
	desc.views[0].texture.sample_type = SG_IMAGESAMPLETYPE_FLOAT;
	desc.samplers[0].stage = SG_SHADERSTAGE_FRAGMENT;
	desc.samplers[0].sampler_type = SG_SAMPLERTYPE_FILTERING;
	desc.texture_sampler_pairs[0].stage = SG_SHADERSTAGE_FRAGMENT;
	desc.texture_sampler_pairs[0].view_slot = 0;
	desc.texture_sampler_pairs[0].sampler_slot = 0;
	desc.texture_sampler_pairs[0].glsl_name = "previous_raindrop";
	desc.label = "matrix-raindrop-shader";
	return desc;
}

static sg_shader_desc symbol_shader_desc(void) {
	sg_shader_desc desc = {0};
	desc.vertex_func.source = fullscreen_vertex_source;
	desc.fragment_func.source = symbol_fragment_source;
	desc.uniform_blocks[0].stage = SG_SHADERSTAGE_FRAGMENT;
	desc.uniform_blocks[0].size = sizeof(lockme_state_params);
	desc.uniform_blocks[0].layout = SG_UNIFORMLAYOUT_STD140;
	desc.uniform_blocks[0].glsl_uniforms[0] = (sg_glsl_shader_uniform){ .type = SG_UNIFORMTYPE_FLOAT4, .array_count = 1, .glsl_name = "grid_time" };
	desc.uniform_blocks[0].glsl_uniforms[1] = (sg_glsl_shader_uniform){ .type = SG_UNIFORMTYPE_FLOAT4, .array_count = 1, .glsl_name = "timing" };
	desc.views[0].texture.stage = SG_SHADERSTAGE_FRAGMENT;
	desc.views[0].texture.image_type = SG_IMAGETYPE_2D;
	desc.views[0].texture.sample_type = SG_IMAGESAMPLETYPE_FLOAT;
	desc.views[1].texture.stage = SG_SHADERSTAGE_FRAGMENT;
	desc.views[1].texture.image_type = SG_IMAGETYPE_2D;
	desc.views[1].texture.sample_type = SG_IMAGESAMPLETYPE_FLOAT;
	desc.samplers[0].stage = SG_SHADERSTAGE_FRAGMENT;
	desc.samplers[0].sampler_type = SG_SAMPLERTYPE_FILTERING;
	desc.texture_sampler_pairs[0].stage = SG_SHADERSTAGE_FRAGMENT;
	desc.texture_sampler_pairs[0].view_slot = 0;
	desc.texture_sampler_pairs[0].sampler_slot = 0;
	desc.texture_sampler_pairs[0].glsl_name = "previous_symbol";
	desc.texture_sampler_pairs[1].stage = SG_SHADERSTAGE_FRAGMENT;
	desc.texture_sampler_pairs[1].view_slot = 1;
	desc.texture_sampler_pairs[1].sampler_slot = 0;
	desc.texture_sampler_pairs[1].glsl_name = "raindrop_state";
	desc.label = "matrix-symbol-shader";
	return desc;
}

static sg_shader_desc final_shader_desc(void) {
	sg_shader_desc desc = {0};
	desc.vertex_func.source = fullscreen_vertex_source;
	desc.fragment_func.source = final_fragment_source;
	desc.uniform_blocks[0].stage = SG_SHADERSTAGE_FRAGMENT;
	desc.uniform_blocks[0].size = sizeof(lockme_final_params);
	desc.uniform_blocks[0].layout = SG_UNIFORMLAYOUT_STD140;
	desc.uniform_blocks[0].glsl_uniforms[0] = (sg_glsl_shader_uniform){ .type = SG_UNIFORMTYPE_FLOAT4, .array_count = 1, .glsl_name = "surface_cell" };
	desc.uniform_blocks[0].glsl_uniforms[1] = (sg_glsl_shader_uniform){ .type = SG_UNIFORMTYPE_FLOAT4, .array_count = 1, .glsl_name = "atlas_time" };
	desc.uniform_blocks[0].glsl_uniforms[2] = (sg_glsl_shader_uniform){ .type = SG_UNIFORMTYPE_FLOAT4, .array_count = 1, .glsl_name = "grid_params" };
	for (int i = 0; i < 3; i++) {
		desc.views[i].texture.stage = SG_SHADERSTAGE_FRAGMENT;
		desc.views[i].texture.image_type = SG_IMAGETYPE_2D;
		desc.views[i].texture.sample_type = SG_IMAGESAMPLETYPE_FLOAT;
	}
	desc.samplers[0].stage = SG_SHADERSTAGE_FRAGMENT;
	desc.samplers[0].sampler_type = SG_SAMPLERTYPE_FILTERING;
	desc.samplers[1].stage = SG_SHADERSTAGE_FRAGMENT;
	desc.samplers[1].sampler_type = SG_SAMPLERTYPE_FILTERING;
	desc.texture_sampler_pairs[0].stage = SG_SHADERSTAGE_FRAGMENT;
	desc.texture_sampler_pairs[0].view_slot = 0;
	desc.texture_sampler_pairs[0].sampler_slot = 0;
	desc.texture_sampler_pairs[0].glsl_name = "raindrop_state";
	desc.texture_sampler_pairs[1].stage = SG_SHADERSTAGE_FRAGMENT;
	desc.texture_sampler_pairs[1].view_slot = 1;
	desc.texture_sampler_pairs[1].sampler_slot = 0;
	desc.texture_sampler_pairs[1].glsl_name = "symbol_state";
	desc.texture_sampler_pairs[2].stage = SG_SHADERSTAGE_FRAGMENT;
	desc.texture_sampler_pairs[2].view_slot = 2;
	desc.texture_sampler_pairs[2].sampler_slot = 1;
	desc.texture_sampler_pairs[2].glsl_name = "glyph_tex";
	desc.label = "matrix-final-shader";
	return desc;
}

static sg_pipeline make_pipeline(sg_shader shader, sg_pixel_format color_format, const char *label) {
	return sg_make_pipeline(&(sg_pipeline_desc){
		.shader = shader,
		.primitive_type = SG_PRIMITIVETYPE_TRIANGLES,
		.depth = {
			.pixel_format = SG_PIXELFORMAT_NONE,
		},
		.colors = {
			[0] = {
				.pixel_format = color_format,
			},
		},
		.sample_count = 1,
		.label = label,
	});
}

static bool init_sokol(const uint8_t *atlas_pixels, int32_t atlas_width, int32_t atlas_height, int32_t glyph_count) {
	if (g_sokol_ready) {
		return true;
	}

	sg_setup(&(sg_desc){
		.environment = {
			.defaults = {
				.color_format = SG_PIXELFORMAT_RGBA8,
				.depth_format = SG_PIXELFORMAT_NONE,
				.sample_count = 1,
			},
		},
		.logger = {
			.func = sokol_logger,
		},
	});
	if (!sg_isvalid()) {
		set_error("sg_setup failed");
		return false;
	}

	sg_image_data img_data = {0};
	img_data.mip_levels[0].ptr = atlas_pixels;
	img_data.mip_levels[0].size = (size_t)atlas_width * (size_t)atlas_height;
	g_atlas_image = sg_make_image(&(sg_image_desc){
		.width = atlas_width,
		.height = atlas_height,
		.pixel_format = SG_PIXELFORMAT_R8,
		.data = img_data,
		.label = "matrix-glyph-atlas",
	});
	g_atlas_view = sg_make_view(&(sg_view_desc){
		.texture = {
			.image = g_atlas_image,
		},
		.label = "matrix-glyph-atlas-view",
	});
	g_atlas_sampler = sg_make_sampler(&(sg_sampler_desc){
		.min_filter = SG_FILTER_LINEAR,
		.mag_filter = SG_FILTER_LINEAR,
		.wrap_u = SG_WRAP_CLAMP_TO_EDGE,
		.wrap_v = SG_WRAP_CLAMP_TO_EDGE,
		.label = "matrix-glyph-sampler",
	});
	g_state_sampler = sg_make_sampler(&(sg_sampler_desc){
		.min_filter = SG_FILTER_NEAREST,
		.mag_filter = SG_FILTER_NEAREST,
		.wrap_u = SG_WRAP_CLAMP_TO_EDGE,
		.wrap_v = SG_WRAP_CLAMP_TO_EDGE,
		.label = "matrix-state-sampler",
	});

	sg_shader_desc rd = raindrop_shader_desc();
	sg_shader_desc sd = symbol_shader_desc();
	sg_shader_desc fd = final_shader_desc();
	g_raindrop_shader = sg_make_shader(&rd);
	g_symbol_shader = sg_make_shader(&sd);
	g_final_shader = sg_make_shader(&fd);
	g_raindrop_pipeline = make_pipeline(g_raindrop_shader, SG_PIXELFORMAT_RGBA8, "matrix-raindrop-pipeline");
	g_symbol_pipeline = make_pipeline(g_symbol_shader, SG_PIXELFORMAT_RGBA8, "matrix-symbol-pipeline");
	g_final_pipeline = make_pipeline(g_final_shader, SG_PIXELFORMAT_RGBA8, "matrix-final-pipeline");

	g_atlas_width = atlas_width;
	g_atlas_height = atlas_height;
	g_atlas_glyph_count = glyph_count;
	if (sg_query_image_state(g_atlas_image) != SG_RESOURCESTATE_VALID ||
			sg_query_view_state(g_atlas_view) != SG_RESOURCESTATE_VALID ||
			sg_query_sampler_state(g_atlas_sampler) != SG_RESOURCESTATE_VALID ||
			sg_query_sampler_state(g_state_sampler) != SG_RESOURCESTATE_VALID ||
			!resource_valid()) {
		destroy_global_resources();
		sg_shutdown();
		set_error(g_last_error[0] == '\0' ? "matrix gpu resource creation failed" : g_last_error);
		return false;
	}

	g_sokol_ready = true;
	return true;
}

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
	int32_t atlas_height) {
	if (!display || !surface || width <= 0 || height <= 0 || cell_width <= 0 || cell_height <= 0 ||
			glyph_count <= 0 || !atlas_pixels || atlas_width <= 0 || atlas_height <= 0) {
		set_error("invalid matrix gpu create arguments");
		return NULL;
	}
	if (g_sokol_ready && (atlas_width != g_atlas_width || atlas_height != g_atlas_height || glyph_count != g_atlas_glyph_count)) {
		set_error("matrix gpu atlas changed after initialization");
		return NULL;
	}
	if (!init_egl(display)) {
		return NULL;
	}

	struct lockme_matrix_gpu *gpu = calloc(1, sizeof(*gpu));
	if (!gpu) {
		set_error("calloc failed");
		return NULL;
	}
	gpu->window = wl_egl_window_create(surface, width, height);
	if (!gpu->window) {
		set_error("wl_egl_window_create failed");
		free(gpu);
		return NULL;
	}
	gpu->surface = eglCreateWindowSurface(g_display, g_config, (EGLNativeWindowType)gpu->window, NULL);
	if (gpu->surface == EGL_NO_SURFACE) {
		set_error("eglCreateWindowSurface failed");
		wl_egl_window_destroy(gpu->window);
		free(gpu);
		return NULL;
	}
	gpu->width = width;
	gpu->height = height;
	gpu->cell_width = cell_width;
	gpu->cell_height = cell_height;
	gpu->glyph_count = glyph_count;

	if (!make_current(gpu) || !init_sokol(atlas_pixels, atlas_width, atlas_height, glyph_count)) {
		eglDestroySurface(g_display, gpu->surface);
		wl_egl_window_destroy(gpu->window);
		free(gpu);
		return NULL;
	}
	g_ref_count++;
	return gpu;
}

int32_t lockme_matrix_gpu_resize(struct lockme_matrix_gpu *gpu, int32_t width, int32_t height) {
	if (!gpu || width <= 0 || height <= 0) {
		set_error("invalid matrix gpu resize arguments");
		return 0;
	}
	if (width == gpu->width && height == gpu->height) {
		return 1;
	}
	wl_egl_window_resize(gpu->window, width, height, 0, 0);
	gpu->width = width;
	gpu->height = height;
	return 1;
}

static void render_state_pass(sg_pipeline pipeline, lockme_state_target *target, sg_bindings bindings, lockme_state_params *params, const char *label) {
	sg_begin_pass(&(sg_pass){
		.action = {
			.colors = {
				[0] = {
					.load_action = SG_LOADACTION_DONTCARE,
				},
			},
		},
		.attachments = {
			.colors = { [0] = target->attachment_view },
		},
		.label = label,
	});
	sg_apply_pipeline(pipeline);
	sg_apply_bindings(&bindings);
	sg_apply_uniforms(0, &(sg_range){ .ptr = params, .size = sizeof(*params) });
	sg_draw(0, 3, 1);
	sg_end_pass();
}

int32_t lockme_matrix_gpu_render(
	struct lockme_matrix_gpu *gpu,
	double time_seconds,
	float fall_speed,
	float cycle_speed,
	float raindrop_length,
	float brightness_decay) {
	if (!gpu || !g_sokol_ready) {
		set_error("matrix gpu renderer is not initialized");
		return 0;
	}
	if (!make_current(gpu)) {
		return 0;
	}
	int32_t fail_after = forced_render_fail_after();
	if (fail_after >= 0 && gpu->frame_count >= (uint32_t)fail_after) {
		set_error("forced matrix gpu render failure");
		return 0;
	}
	if (!ensure_state(gpu)) {
		return 0;
	}

	sg_reset_state_cache();
	lockme_state_params state_params = {
		.grid_time = { (float)gpu->grid_width, (float)gpu->grid_height, (float)time_seconds, (float)gpu->frame_count },
		.timing = { fall_speed, cycle_speed, raindrop_length, brightness_decay },
	};
	int raindrop_src = gpu->current_raindrop;
	int raindrop_dst = 1 - raindrop_src;
	render_state_pass(
		g_raindrop_pipeline,
		&gpu->raindrop[raindrop_dst],
		(sg_bindings){
			.views = { [0] = gpu->raindrop[raindrop_src].texture_view },
			.samplers = { [0] = g_state_sampler },
		},
		&state_params,
		"matrix-raindrop-pass");
	gpu->current_raindrop = raindrop_dst;

	lockme_state_params symbol_params = {
		.grid_time = { (float)gpu->grid_width, (float)gpu->grid_height, (float)time_seconds, (float)gpu->frame_count },
		.timing = { fall_speed, cycle_speed, raindrop_length, (float)gpu->glyph_count },
	};
	int symbol_src = gpu->current_symbol;
	int symbol_dst = 1 - symbol_src;
	render_state_pass(
		g_symbol_pipeline,
		&gpu->symbol[symbol_dst],
		(sg_bindings){
			.views = {
				[0] = gpu->symbol[symbol_src].texture_view,
				[1] = gpu->raindrop[gpu->current_raindrop].texture_view,
			},
			.samplers = { [0] = g_state_sampler },
		},
		&symbol_params,
		"matrix-symbol-pass");
	gpu->current_symbol = symbol_dst;

	lockme_final_params final_params = {
		.surface_cell = { (float)gpu->width, (float)gpu->height, (float)gpu->cell_width, (float)gpu->cell_height },
		.atlas_time = { (float)g_atlas_width, (float)g_atlas_height, (float)gpu->glyph_count, (float)time_seconds },
		.grid_params = { (float)gpu->grid_width, (float)gpu->grid_height, 0.0f, 0.0f },
	};
	sg_begin_pass(&(sg_pass){
		.action = {
			.colors = {
				[0] = {
					.load_action = SG_LOADACTION_CLEAR,
					.clear_value = { 0.0f, 0.0f, 0.0f, 1.0f },
				},
			},
		},
		.swapchain = {
			.width = gpu->width,
			.height = gpu->height,
			.sample_count = 1,
			.color_format = SG_PIXELFORMAT_RGBA8,
			.depth_format = SG_PIXELFORMAT_NONE,
			.gl = { .framebuffer = 0 },
		},
		.label = "matrix-final-pass",
	});
	sg_apply_pipeline(g_final_pipeline);
	sg_apply_bindings(&(sg_bindings){
		.views = {
			[0] = gpu->raindrop[gpu->current_raindrop].texture_view,
			[1] = gpu->symbol[gpu->current_symbol].texture_view,
			[2] = g_atlas_view,
		},
		.samplers = {
			[0] = g_state_sampler,
			[1] = g_atlas_sampler,
		},
	});
	sg_apply_uniforms(0, &(sg_range){ .ptr = &final_params, .size = sizeof(final_params) });
	sg_draw(0, 3, 1);
	sg_end_pass();
	sg_commit();
	gpu->frame_count++;

	if (!eglSwapBuffers(g_display, gpu->surface)) {
		set_error("eglSwapBuffers failed");
		return 0;
	}
	return 1;
}

void lockme_matrix_gpu_destroy(struct lockme_matrix_gpu *gpu) {
	if (!gpu) {
		return;
	}
	if (g_sokol_ready && g_display != EGL_NO_DISPLAY && gpu->surface != EGL_NO_SURFACE && make_current(gpu)) {
		destroy_state(gpu);
	}
	if (g_display != EGL_NO_DISPLAY && gpu->surface != EGL_NO_SURFACE) {
		eglDestroySurface(g_display, gpu->surface);
	}
	if (gpu->window) {
		wl_egl_window_destroy(gpu->window);
	}
	free(gpu);
	if (g_ref_count > 0) {
		g_ref_count--;
	}
	if (g_ref_count == 0 && g_display != EGL_NO_DISPLAY) {
		if (g_sokol_ready) {
			destroy_global_resources();
			sg_shutdown();
			g_sokol_ready = false;
		}
		eglMakeCurrent(g_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
		if (g_context != EGL_NO_CONTEXT) {
			eglDestroyContext(g_display, g_context);
			g_context = EGL_NO_CONTEXT;
		}
		eglTerminate(g_display);
		g_display = EGL_NO_DISPLAY;
		g_config = NULL;
		g_atlas_width = 0;
		g_atlas_height = 0;
		g_atlas_glyph_count = 0;
	}
}

const char *lockme_matrix_gpu_last_error(void) {
	if (g_last_error[0] == '\0') {
		return "unknown matrix gpu error";
	}
	return g_last_error;
}
