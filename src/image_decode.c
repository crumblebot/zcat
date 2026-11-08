/* stb_image is pinned in vendor/stb_image.h; see THIRD_PARTY.md. */
#include <stdlib.h>
#include <stddef.h>
#include <sys/ioctl.h>
#include <unistd.h>
/* A hard budget also covers decoder intermediates, not just returned pixels. */
typedef union { max_align_t align; size_t size; } allocation;
static size_t used;
static void *bounded_malloc(size_t n) {
    if (n > 128u * 1024u * 1024u - used) return NULL;
    allocation *p = malloc(sizeof(allocation) + n);
    if (!p) return NULL;
    p->size = n; used += n; return p + 1;
}
static void bounded_free(void *ptr) {
    if (!ptr) return;
    allocation *p = (allocation *)ptr - 1;
    used -= p->size; free(p);
}
static void *bounded_realloc(void *ptr, size_t n) {
    if (!ptr) return bounded_malloc(n);
    allocation *p = (allocation *)ptr - 1;
    if (n > 128u * 1024u * 1024u - (used - p->size)) return NULL;
    size_t old = p->size;
    p = realloc(p, sizeof(allocation) + n);
    if (!p) return NULL;
    p->size = n; used = used - old + n; return p + 1;
}
#define STBI_MALLOC bounded_malloc
#define STBI_REALLOC bounded_realloc
#define STBI_FREE bounded_free
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#define STBI_NO_STDIO
#define STBI_NO_HDR
#define STBI_NO_LINEAR
#define STBI_MAX_DIMENSIONS 8192
#define STB_IMAGE_IMPLEMENTATION
#include "vendor/stb_image.h"
void zc_window_size(unsigned short *values) {
    struct winsize ws = {0};
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0) {
        values[0] = ws.ws_col; values[1] = ws.ws_row;
        values[2] = ws.ws_xpixel; values[3] = ws.ws_ypixel;
    }
}
