/* Byte API (REG_USEBYTES): tre_regncompb + tre_regnexecb + tre_regaexecb (layout: fuzz_common.h). */
#include "fuzz_common.h"

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
  regamatch_t am;

  if (fuzz_split(data, size, &in))
    return -1;
  if (tre_regncompb(&re, (const char *)in.pat, in.pat_len, in.cflags) != REG_OK)
    return 0;
  tre_regnexecb(&re, (const char *)in.subj, in.subj_len, FUZZ_NMATCH, pm, in.eflags);
  /* tre_regaexecb takes a NUL-terminated string: give it a terminated copy. */
  char *s = malloc(in.subj_len + 1);
  if (s) {
    memcpy(s, in.subj, in.subj_len);
    s[in.subj_len] = '\0';
    memset(&am, 0, sizeof(am));
    am.nmatch = FUZZ_NMATCH;
    am.pmatch = pm;
    tre_regaexecb(&re, s, &am, in.params, in.eflags);
    free(s);
  }
  tre_regfree(&re);
  return 0;
}
