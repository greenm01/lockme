#include "matrix_font_shim.h"

#include <fontconfig/fontconfig.h>
#include <ft2build.h>
#include FT_FREETYPE_H

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

struct lockme_matrix_font {
	FT_Library library;
	FT_Face face;
};

static char *lockme_strdup(const char *value) {
	if (value == NULL) {
		return NULL;
	}
	size_t len = strlen(value);
	char *copy = malloc(len + 1);
	if (copy == NULL) {
		return NULL;
	}
	memcpy(copy, value, len + 1);
	return copy;
}

static char *resolve_font_file(const char *family) {
	const char *name = (family != NULL && family[0] != '\0') ? family : "monospace";
	FcPattern *pattern = FcNameParse((const FcChar8 *) name);
	if (pattern == NULL) {
		return NULL;
	}
	FcConfigSubstitute(NULL, pattern, FcMatchPattern);
	FcDefaultSubstitute(pattern);
	FcResult result;
	FcPattern *match = FcFontMatch(NULL, pattern, &result);
	FcPatternDestroy(pattern);
	if (match == NULL) {
		return NULL;
	}
	FcChar8 *file = NULL;
	char *resolved = NULL;
	if (FcPatternGetString(match, FC_FILE, 0, &file) == FcResultMatch && file != NULL) {
		resolved = lockme_strdup((const char *) file);
	}
	FcPatternDestroy(match);
	return resolved;
}

struct lockme_matrix_font *lockme_matrix_font_open(const char *family, const char *path, int32_t pixel_size) {
	if (pixel_size <= 0) {
		return NULL;
	}
	struct lockme_matrix_font *font = calloc(1, sizeof(*font));
	if (font == NULL) {
		return NULL;
	}
	if (FT_Init_FreeType(&font->library) != 0) {
		free(font);
		return NULL;
	}

	char *font_path = NULL;
	if (path != NULL && path[0] != '\0') {
		font_path = lockme_strdup(path);
	} else {
		font_path = resolve_font_file(family);
	}
	if (font_path == NULL) {
		lockme_matrix_font_close(font);
		return NULL;
	}

	int face_rc = FT_New_Face(font->library, font_path, 0, &font->face);
	free(font_path);
	if (face_rc != 0) {
		lockme_matrix_font_close(font);
		return NULL;
	}
	if (FT_Set_Pixel_Sizes(font->face, 0, (FT_UInt) pixel_size) != 0) {
		lockme_matrix_font_close(font);
		return NULL;
	}
	return font;
}

void lockme_matrix_font_close(struct lockme_matrix_font *font) {
	if (font == NULL) {
		return;
	}
	if (font->face != NULL) {
		FT_Done_Face(font->face);
	}
	if (font->library != NULL) {
		FT_Done_FreeType(font->library);
	}
	free(font);
}

int32_t lockme_matrix_font_metrics(struct lockme_matrix_font *font, int32_t *cell_width, int32_t *line_height, int32_t *baseline) {
	if (font == NULL || font->face == NULL || cell_width == NULL || line_height == NULL || baseline == NULL) {
		return -1;
	}
	int32_t width = 1;
	if (FT_Load_Char(font->face, 'M', FT_LOAD_DEFAULT) == 0) {
		width = (int32_t) ((font->face->glyph->advance.x + 32) >> 6);
	}
	if (width < 1) {
		width = 1;
	}
	int32_t natural_line = (int32_t) ((font->face->size->metrics.height + 32) >> 6);
	int32_t base = (int32_t) ((font->face->size->metrics.ascender + 32) >> 6);
	*cell_width = width;
	*line_height = natural_line > 0 ? natural_line : 1;
	*baseline = base > 0 ? base : *line_height;
	return 0;
}

static uint32_t decode_utf8_first(const char *utf8) {
	if (utf8 == NULL || utf8[0] == '\0') {
		return 0;
	}
	const unsigned char *s = (const unsigned char *) utf8;
	if (s[0] < 0x80) {
		return s[0];
	}
	if ((s[0] & 0xe0) == 0xc0 && (s[1] & 0xc0) == 0x80) {
		return ((uint32_t) (s[0] & 0x1f) << 6) | (uint32_t) (s[1] & 0x3f);
	}
	if ((s[0] & 0xf0) == 0xe0 && (s[1] & 0xc0) == 0x80 && (s[2] & 0xc0) == 0x80) {
		return ((uint32_t) (s[0] & 0x0f) << 12) | ((uint32_t) (s[1] & 0x3f) << 6) | (uint32_t) (s[2] & 0x3f);
	}
	if ((s[0] & 0xf8) == 0xf0 && (s[1] & 0xc0) == 0x80 && (s[2] & 0xc0) == 0x80 && (s[3] & 0xc0) == 0x80) {
		return ((uint32_t) (s[0] & 0x07) << 18) | ((uint32_t) (s[1] & 0x3f) << 12) | ((uint32_t) (s[2] & 0x3f) << 6) | (uint32_t) (s[3] & 0x3f);
	}
	return 0;
}

int32_t lockme_matrix_font_rasterize(struct lockme_matrix_font *font, const char *utf8, struct lockme_matrix_glyph *glyph) {
	if (font == NULL || font->face == NULL || glyph == NULL) {
		return -1;
	}
	memset(glyph, 0, sizeof(*glyph));
	uint32_t codepoint = decode_utf8_first(utf8);
	if (codepoint == 0) {
		return -1;
	}
	FT_UInt glyph_index = FT_Get_Char_Index(font->face, codepoint);
	if (glyph_index == 0) {
		glyph_index = FT_Get_Char_Index(font->face, '?');
	}
	if (glyph_index == 0 || FT_Load_Glyph(font->face, glyph_index, FT_LOAD_DEFAULT) != 0) {
		return -1;
	}
	if (FT_Render_Glyph(font->face->glyph, FT_RENDER_MODE_NORMAL) != 0) {
		return -1;
	}

	FT_GlyphSlot slot = font->face->glyph;
	FT_Bitmap *bitmap = &slot->bitmap;
	int width = (int) bitmap->width;
	int height = (int) bitmap->rows;
	int pitch = bitmap->pitch < 0 ? -bitmap->pitch : bitmap->pitch;
	uint8_t *pixels = NULL;
	if (width > 0 && height > 0) {
		pixels = malloc((size_t) width * (size_t) height);
		if (pixels == NULL) {
			return -1;
		}
		for (int row = 0; row < height; row++) {
			const uint8_t *src = bitmap->buffer + (bitmap->pitch < 0 ? (height - 1 - row) * pitch : row * pitch);
			memcpy(pixels + (size_t) row * (size_t) width, src, (size_t) width);
		}
	}

	glyph->width = width;
	glyph->height = height;
	glyph->left = slot->bitmap_left;
	glyph->top = slot->bitmap_top;
	glyph->advance = (int32_t) ((slot->advance.x + 32) >> 6);
	glyph->pixels = pixels;
	return 0;
}

void lockme_matrix_glyph_free(struct lockme_matrix_glyph *glyph) {
	if (glyph == NULL) {
		return;
	}
	free(glyph->pixels);
	memset(glyph, 0, sizeof(*glyph));
}
