#ifndef LOCKME_MATRIX_FONT_SHIM_H
#define LOCKME_MATRIX_FONT_SHIM_H

#include <stdint.h>

struct lockme_matrix_font;

struct lockme_matrix_glyph {
	int32_t width;
	int32_t height;
	int32_t left;
	int32_t top;
	int32_t advance;
	uint8_t *pixels;
};

struct lockme_matrix_font *lockme_matrix_font_open(const char *family, const char *path, int32_t pixel_size);
void lockme_matrix_font_close(struct lockme_matrix_font *font);
int32_t lockme_matrix_font_metrics(struct lockme_matrix_font *font, int32_t *cell_width, int32_t *line_height, int32_t *baseline);
int32_t lockme_matrix_font_rasterize(struct lockme_matrix_font *font, const char *utf8, struct lockme_matrix_glyph *glyph);
void lockme_matrix_glyph_free(struct lockme_matrix_glyph *glyph);

#endif
