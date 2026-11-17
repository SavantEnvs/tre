/* Multibyte API: tre_regncomp + tre_regnexec + tre_reganexec (layout: fuzz_common.h). */
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
  if (tre_regncomp(&re, (const char *)in.pat, in.pat_len, in.cflags) != REG_OK)
    return 0;
  tre_regnexec(&re, (const char *)in.subj, in.subj_len, FUZZ_NMATCH, pm, in.eflags);
  memset(&am, 0, sizeof(am));
  am.nmatch = FUZZ_NMATCH;
  am.pmatch = pm;
  tre_reganexec(&re, (const char *)in.subj, in.subj_len, &am, in.params, in.eflags);
  tre_regfree(&re);
  return 0;
}
