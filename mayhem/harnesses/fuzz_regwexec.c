/* Wide API: tre_regwncomp + tre_regwnexec + tre_regawnexec. The pattern and the subject are raw
   wchar_t arrays (sizeof(wchar_t) bytes per character, any value), so code points mbrtowc() would
   never produce reach the parser and matchers too. Layout: fuzz_common.h, lengths in bytes. */
#include "fuzz_common.h"
#include <wchar.h>

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
  (void)argc; (void)argv;
  fuzz_set_locale();
  return 0;
}

static wchar_t *to_wide(const uint8_t *p, size_t n, size_t *wlen)
{
  *wlen = n / sizeof(wchar_t);
  wchar_t *w = malloc((*wlen + 1) * sizeof(wchar_t));
  if (!w)
    return NULL;
  memcpy(w, p, *wlen * sizeof(wchar_t));
  w[*wlen] = 0;
  return w;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
  fuzz_input in;
  regex_t re;
  regmatch_t pm[FUZZ_NMATCH];
  regamatch_t am;
  size_t plen, slen;

  if (fuzz_split(data, size, &in))
    return -1;
  wchar_t *pat = to_wide(in.pat, in.pat_len, &plen);
  wchar_t *subj = to_wide(in.subj, in.subj_len, &slen);
  if (pat && subj && tre_regwncomp(&re, pat, plen, in.cflags) == REG_OK) {
    tre_regwnexec(&re, subj, slen, FUZZ_NMATCH, pm, in.eflags);
    memset(&am, 0, sizeof(am));
    am.nmatch = FUZZ_NMATCH;
    am.pmatch = pm;
    tre_regawnexec(&re, subj, slen, &am, in.params, in.eflags);
    tre_regfree(&re);
  }
  free(pat);
  free(subj);
  return 0;
}
