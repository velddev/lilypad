// lilypad-regions: find rectangular UI elements in a screenshot.
//
//   lilypad-regions <image.ppm>   ->   JSON [[x,y,w,h], ...] in image pixels, smallest first
//   lilypad-regions --windows <image.ppm>
//                              ->   boxes of everything that is not the wallpaper,
//                                   for finding windows in niri's overview
//   lilypad-regions --crop WxH+X+Y <image.ppm> <out.png>
//                              ->   that part of the image, as a PNG
//
// Neighbouring pixels of near-identical colour are joined into regions
// (union-find). Flat UI pieces (sidebars, panels, buttons, inputs, cards)
// become one region each; text and icons become small, irregular ones.
// A region is kept when its bounding box is big enough and the region
// actually runs along most of that box's edges, i.e. it looks like a
// rectangle (filled or outlined, rounded corners allowed).
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

#define TOLERANCE 4        // max per-channel difference between joined neighbours
#define MIN_SIDE 32        // smallest element side, in pixels
#define MIN_AREA 4096      // smallest element box area
#define EDGE_RATIO 0.55    // share of the box perimeter the region must touch
#define SAME_EDGE 2        // boxes whose edges all lie this close are duplicates
#define DIVIDER 4          // widest separator line between two parts of one element
#define MAX_BOXES 8192     // cap on boxes after joining
#define NEST_RATIO 1.25    // drop a box when a box around it is at most this much bigger

static uint32_t *parent;

static uint32_t find(uint32_t a) {
  while (parent[a] != a) {
    parent[a] = parent[parent[a]];
    a = parent[a];
  }
  return a;
}

static void join(uint32_t a, uint32_t b) {
  a = find(a);
  b = find(b);
  if (a != b) {
    if (a < b) parent[b] = a;
    else parent[a] = b;
  }
}

static int read_token(FILE *f) {
  int c, v = 0;
  do {
    c = fgetc(f);
    if (c == '#') while (c != '\n' && c != EOF) c = fgetc(f);
  } while (c == ' ' || c == '\n' || c == '\r' || c == '\t');
  while (c >= '0' && c <= '9') {
    v = v * 10 + (c - '0');
    c = fgetc(f);
  }
  return v;
}

static uint8_t *read_ppm(const char *path, int *w, int *h) {
  FILE *f = fopen(path, "rb");
  if (!f) { perror(path); return NULL; }
  uint8_t *px = NULL;
  if (fgetc(f) != 'P' || fgetc(f) != '6') { fprintf(stderr, "not a P6 ppm\n"); goto done; }
  *w = read_token(f);
  *h = read_token(f);
  int maxval = read_token(f);
  if (*w <= 0 || *h <= 0 || maxval != 255) { fprintf(stderr, "unsupported ppm\n"); goto done; }
  size_t n = (size_t)*w * *h;
  px = malloc(n * 3);
  if (!px || fread(px, 3, n, f) != n) {
    fprintf(stderr, "short read\n");
    free(px);
    px = NULL;
  }
done:
  fclose(f);
  return px;
}

static void put32(uint8_t *p, uint32_t v) {
  p[0] = v >> 24;
  p[1] = v >> 16;
  p[2] = v >> 8;
  p[3] = v;
}

static void chunk(FILE *f, const char *type, const uint8_t *data, uint32_t len) {
  uint8_t word[4];
  put32(word, len);
  fwrite(word, 1, 4, f);
  fwrite(type, 1, 4, f);
  fwrite(data, 1, len, f);
  put32(word, crc32(crc32(0, (const uint8_t *)type, 4), data, len));
  fwrite(word, 1, 4, f);
}

// PNG's Paeth predictor: whichever of left, up and up-left is closest to left + up - upleft.
static int paeth(int a, int b, int c) {
  int pa = abs(b - c), pb = abs(a - c), pc = abs(a + b - 2 * c);
  return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
}

// Writes `stride` bytes of one row as filter `type`, and returns how large the result looks:
// the sum of the bytes as signed numbers, where smaller compresses better.
static uint64_t filter_row(uint8_t *out, int type, const uint8_t *row, const uint8_t *up, size_t stride) {
  uint64_t cost = 0;
  for (size_t i = 0; i < stride; i++) {
    int a = i >= 3 ? row[i - 3] : 0, b = up ? up[i] : 0, c = up && i >= 3 ? up[i - 3] : 0;
    uint8_t v = row[i] - (type == 1 ? a : type == 2 ? b : type == 4 ? paeth(a, b, c) : 0);
    out[i] = v;
    cost += v < 128 ? v : 256 - v;
  }
  return cost;
}

static int crop(const char *geometry, const char *in, const char *out) {
  int cw, ch, cx, cy, w, h;
  if (sscanf(geometry, "%dx%d+%d+%d", &cw, &ch, &cx, &cy) != 4 || cw <= 0 || ch <= 0 || cx < 0 || cy < 0) {
    fprintf(stderr, "bad crop: %s\n", geometry);
    return 2;
  }
  uint8_t *px = read_ppm(in, &w, &h);
  if (!px) return 1;
  // Rounding a fractional scale can land a pixel past the edge.
  if (cx >= w || cy >= h) { fprintf(stderr, "crop is outside the image\n"); return 1; }
  if (cw > w - cx) cw = w - cx;
  if (ch > h - cy) ch = h - cy;

  size_t stride = (size_t)cw * 3, raw_size = (stride + 1) * ch;
  uint8_t *raw = malloc(raw_size), *trial = malloc(stride);
  uLongf packed_size = compressBound(raw_size);
  uint8_t *packed = malloc(packed_size);
  if (!raw || !trial || !packed) { fprintf(stderr, "out of memory\n"); return 1; }

  for (int y = 0; y < ch; y++) {
    const uint8_t *row = px + ((size_t)(cy + y) * w + cx) * 3;
    const uint8_t *up = y ? row - (size_t)w * 3 : NULL;
    uint8_t *dest = raw + (stride + 1) * y;
    uint64_t best = UINT64_MAX;
    for (int type = 0; type <= 4; type++) {
      if (type == 3) continue;  // Average rarely wins on screens
      uint64_t cost = filter_row(trial, type, row, up, stride);
      if (cost < best) {
        best = cost;
        dest[0] = type;
        memcpy(dest + 1, trial, stride);
      }
    }
  }
  if (compress2(packed, &packed_size, raw, raw_size, 6) != Z_OK) {
    fprintf(stderr, "compress failed\n");
    return 1;
  }

  FILE *f = fopen(out, "wb");
  if (!f) { perror(out); return 1; }
  uint8_t header[13];
  put32(header, cw);
  put32(header + 4, ch);
  memcpy(header + 8, "\x08\x02\x00\x00\x00", 5);  // 8-bit RGB, no interlacing
  fwrite("\x89PNG\r\n\x1a\n", 1, 8, f);
  chunk(f, "IHDR", header, sizeof header);
  chunk(f, "IDAT", packed, packed_size);
  chunk(f, "IEND", (const uint8_t *)"", 0);  // crc32 ignores a NULL buffer
  if (fclose(f) != 0) { perror(out); return 1; }
  return 0;
}

typedef struct { int x0, y0, x1, y1; uint32_t count, edge; } Box;

static long area(const Box *b) { return (long)(b->x1 - b->x0 + 1) * (b->y1 - b->y0 + 1); }

static int by_area(const void *a, const void *b) {
  long pa = area(a), qa = area(b);
  return (pa > qa) - (pa < qa);
}

static int near(int a, int b) { return abs(a - b) <= SAME_EDGE; }

static int same_box(const Box *a, const Box *b) {
  return near(a->x0, b->x0) && near(a->y0, b->y0) && near(a->x1, b->x1) && near(a->y1, b->y1);
}

// a sits directly above (vertical) or left of b, same width / height, with at
// most a thin divider between them.
static int stacked(const Box *a, const Box *b, int vertical) {
  if (vertical)
    return near(a->x0, b->x0) && near(a->x1, b->x1) && b->y0 > a->y1 && b->y0 - a->y1 - 1 <= DIVIDER;
  return near(a->y0, b->y0) && near(a->y1, b->y1) && b->x0 > a->x1 && b->x0 - a->x1 - 1 <= DIVIDER;
}

// A divider line splits a panel's flat background into separate regions
// (search bar / list, title bar / content, sidebar / main). Add the box
// around each maximal run of such parts so the whole panel can be picked.
// Alternate directions until nothing new appears, so nested splits combine.
static uint32_t join_parts(Box **boxes, uint32_t count) {
  Box *box = *boxes;
  uint32_t *group = malloc(count * sizeof *group);
  for (int round = 0, quiet = 0; round < 8 && quiet < 2; round++) {
    int vertical = round % 2 == 0;
    uint32_t n = count;
    group = realloc(group, n * sizeof *group);
    for (uint32_t i = 0; i < n; i++) group[i] = i;
    for (uint32_t i = 0; i < n; i++)
      for (uint32_t j = 0; j < n; j++)
        if (i != j && stacked(&box[i], &box[j], vertical)) {
          uint32_t a = i, b = j;
          while (group[a] != a) a = group[a];
          while (group[b] != b) b = group[b];
          if (a != b) group[a > b ? a : b] = a < b ? a : b;
        }
    uint32_t added = 0;
    for (uint32_t r = 0; r < n && count < MAX_BOXES; r++) {
      Box u = {0};
      int members = 0;
      for (uint32_t i = 0; i < n; i++) {
        uint32_t g = i;
        while (group[g] != g) g = group[g];
        if (g != r) continue;
        if (members++ == 0) u = box[i];
        if (box[i].x0 < u.x0) u.x0 = box[i].x0;
        if (box[i].y0 < u.y0) u.y0 = box[i].y0;
        if (box[i].x1 > u.x1) u.x1 = box[i].x1;
        if (box[i].y1 > u.y1) u.y1 = box[i].y1;
      }
      if (members < 2) continue;
      int dup = 0;
      for (uint32_t i = 0; i < count && !dup; i++) dup = same_box(&u, &box[i]);
      if (dup) continue;
      box = realloc(box, (count + 1) * sizeof *box);
      box[count++] = u;
      added++;
    }
    quiet = added ? 0 : quiet + 1;
  }
  free(group);
  *boxes = box;
  return count;
}

// Overview mode: the wallpaper is the biggest flat region. Join everything
// else into blobs and print each blob's box: the zoomed-out windows (plus
// whatever shell surfaces sit on top, which the caller filters out).
static int print_blobs(uint32_t *label, const Box *box, uint32_t boxes, int w, int h) {
  size_t n = (size_t)w * h;
  uint32_t bg = 0;
  for (uint32_t b = 1; b < boxes; b++)
    if (box[b].count > box[bg].count) bg = b;
  parent = malloc(n * sizeof *parent);
  for (size_t i = 0; i < n; i++) parent[i] = (uint32_t)i;
  for (int y = 0; y < h; y++)
    for (int x = 0; x < w; x++) {
      size_t i = (size_t)y * w + x;
      if (label[i] == bg) continue;
      if (x + 1 < w && label[i + 1] != bg) join(i, i + 1);
      if (y + 1 < h && label[i + w] != bg) join(i, i + w);
    }
  // Roots are each set's smallest index, so they are relabelled before their members.
  uint32_t blobs = 0;
  for (size_t i = 0; i < n; i++) {
    if (label[i] == bg) { label[i] = UINT32_MAX; continue; }
    uint32_t r = find(i);
    label[i] = (r == i) ? blobs++ : label[r];
  }
  Box *blob = malloc((blobs ? blobs : 1) * sizeof *blob);
  for (uint32_t b = 0; b < blobs; b++) blob[b] = (Box){w, h, -1, -1, 0, 0};
  for (int y = 0; y < h; y++)
    for (int x = 0; x < w; x++) {
      uint32_t l = label[(size_t)y * w + x];
      if (l == UINT32_MAX) continue;
      Box *b = &blob[l];
      if (x < b->x0) b->x0 = x;
      if (x > b->x1) b->x1 = x;
      if (y < b->y0) b->y0 = y;
      if (y > b->y1) b->y1 = y;
      b->count++;
    }
  printf("[");
  int first = 1;
  for (uint32_t b = 0; b < blobs; b++) {
    int bw = blob[b].x1 - blob[b].x0 + 1, bh = blob[b].y1 - blob[b].y0 + 1;
    if (bw < MIN_SIDE || bh < MIN_SIDE) continue;
    printf("%s[%d,%d,%d,%d]", first ? "" : ",", blob[b].x0, blob[b].y0, bw, bh);
    first = 0;
  }
  printf("]\n");
  return 0;
}

int main(int argc, char **argv) {
  if (argc == 5 && strcmp(argv[1], "--crop") == 0) return crop(argv[2], argv[3], argv[4]);
  int windows_mode = argc >= 3 && strcmp(argv[1], "--windows") == 0;
  if (argc < 2 || (argc >= 3 && !windows_mode)) {
    fprintf(stderr, "usage: lilypad-regions [--windows] image.ppm\n"
                    "       lilypad-regions --crop WxH+X+Y image.ppm out.png\n");
    return 2;
  }
  int w, h;
  uint8_t *px = read_ppm(argv[windows_mode ? 2 : 1], &w, &h);
  if (!px) return 1;
  size_t n = (size_t)w * h;

  parent = malloc(n * sizeof *parent);
  for (size_t i = 0; i < n; i++) parent[i] = (uint32_t)i;

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      size_t i = (size_t)y * w + x;
      const uint8_t *p = px + i * 3;
      if (x + 1 < w) {
        const uint8_t *q = p + 3;
        if (abs(p[0] - q[0]) <= TOLERANCE && abs(p[1] - q[1]) <= TOLERANCE && abs(p[2] - q[2]) <= TOLERANCE)
          join(i, i + 1);
      }
      if (y + 1 < h) {
        const uint8_t *q = p + (size_t)w * 3;
        if (abs(p[0] - q[0]) <= TOLERANCE && abs(p[1] - q[1]) <= TOLERANCE && abs(p[2] - q[2]) <= TOLERANCE)
          join(i, i + w);
      }
    }
  }
  free(px);

  // Compact labels: reuse a second array mapping root -> box index.
  uint32_t *label = malloc(n * sizeof *label);
  uint32_t boxes = 0;
  for (size_t i = 0; i < n; i++) {
    uint32_t r = find(i);
    label[i] = (r == i) ? boxes++ : label[r];
  }
  free(parent);

  Box *box = malloc(boxes * sizeof *box);
  for (uint32_t b = 0; b < boxes; b++) box[b] = (Box){w, h, -1, -1, 0, 0};
  for (int y = 0; y < h; y++)
    for (int x = 0; x < w; x++) {
      Box *b = &box[label[(size_t)y * w + x]];
      if (x < b->x0) b->x0 = x;
      if (x > b->x1) b->x1 = x;
      if (y < b->y0) b->y0 = y;
      if (y > b->y1) b->y1 = y;
      b->count++;
    }
  if (windows_mode) return print_blobs(label, box, boxes, w, h);
  // Count pixels lying on each region's own bounding-box border.
  for (int y = 0; y < h; y++)
    for (int x = 0; x < w; x++) {
      Box *b = &box[label[(size_t)y * w + x]];
      if (x == b->x0 || x == b->x1 || y == b->y0 || y == b->y1) b->edge++;
    }
  free(label);

  uint32_t kept = 0;
  for (uint32_t b = 0; b < boxes; b++) {
    int bw = box[b].x1 - box[b].x0 + 1, bh = box[b].y1 - box[b].y0 + 1;
    if (bw < MIN_SIDE || bh < MIN_SIDE || (long)bw * bh < MIN_AREA) continue;
    double perimeter = 2.0 * (bw + bh) - 4;
    if (box[b].edge < EDGE_RATIO * perimeter) continue;
    box[kept++] = box[b];
  }
  kept = join_parts(&box, kept);
  qsort(box, kept, sizeof *box, by_area);

  // Drop duplicates, and boxes barely smaller than one around them (a panel
  // and its padded frame), so each scroll step is a real jump in size.
  printf("[");
  int first = 1;
  for (uint32_t i = 0; i < kept; i++) {
    int dup = 0;
    for (uint32_t j = i + 1; j < kept && !dup; j++)
      dup = same_box(&box[i], &box[j])
          || (box[j].x0 <= box[i].x0 && box[j].y0 <= box[i].y0
              && box[j].x1 >= box[i].x1 && box[j].y1 >= box[i].y1
              && area(&box[j]) <= NEST_RATIO * area(&box[i]));
    if (dup) continue;
    printf("%s[%d,%d,%d,%d]", first ? "" : ",", box[i].x0, box[i].y0,
           box[i].x1 - box[i].x0 + 1, box[i].y1 - box[i].y0 + 1);
    first = 0;
  }
  printf("]\n");
  return 0;
}
