/* User string source: tre_regncomp + tre_reguexec over a tre_str_source whose callbacks read the
   subject bytes (one byte per character, like tests/test-str-source.c, but bounded by length
   rather than a NUL). Back references go through the compare() callback. Layout: fuzz_common.h. */
#include "fuzz_common.h"

typedef struct {
  const uint8_t *s;
  size_t len;
  size_t pos;
} src_ctx;

static int src_next(tre_char_t *c, unsigned int *pos_add, void *context)
{
  src_ctx *ctx = context;
  *pos_add = 1;
  if (ctx->pos >= ctx->len) {
    *c = 0;
    return 1;
  }
  *c = ctx->s[ctx->pos++];
  return 0;
}

static void src_rewind(size_t pos, void *context)
{
  src_ctx *ctx = context;
  ctx->pos = pos;
}

static int src_compare(size_t pos1, size_t pos2, size_t len, void *context)
{
  src_ctx *ctx = context;
  if (pos1 > ctx->len || pos2 > ctx->len || len > ctx->len - pos1 || len > ctx->len - pos2)
    return 1;
  return memcmp(ctx->s + pos1, ctx->s + pos2, len);
}

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
  (void)argc; (void)argv;
  fuzz_set_locale();
  return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
  fuzz_input in;
  regex_t re;
  regmatch_t pm[FUZZ_NMATCH];

  if (fuzz_split(data, size, &in))
    return -1;
  if (tre_regncomp(&re, (const char *)in.pat, in.pat_len, in.cflags) != REG_OK)
    return 0;
  src_ctx ctx = { in.subj, in.subj_len, 0 };
  tre_str_source src = { src_next, src_rewind, src_compare, &ctx };
  tre_reguexec(&re, &src, FUZZ_NMATCH, pm, in.eflags);
  tre_regfree(&re);
  return 0;
}
