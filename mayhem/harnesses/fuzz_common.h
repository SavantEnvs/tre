/*
 * Shared input layout for the TRE libFuzzer harnesses (mayhem/harnesses/).
 *
 *   byte 0      cflags  (REG_EXTENDED|ICASE|NEWLINE|NOSUB|LITERAL|RIGHT_ASSOC|UNGREEDY; the
 *               harness decides REG_USEBYTES itself)
 *   byte 1      low nibble: eflags (NOTBOL|NOTEOL|APPROX_MATCHER|BACKTRACKING_MATCHER)
 *               high nibble: max_cost for the approximate matcher
 *   bytes 2..3  pattern length (little endian), clamped to what is left
 *   then        the pattern, then the subject string (the rest of the input)
 *
 * Every input is handled independently: nothing is kept between calls except the locale, which is
 * set once in LLVMFuzzerInitialize and never changed.
 */
#ifndef TRE_FUZZ_COMMON_H
#define TRE_FUZZ_COMMON_H

#include <locale.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <tre/tre.h>

#define FUZZ_NMATCH 10

typedef struct {
  int cflags;
  int eflags;
  regaparams_t params;
  const uint8_t *pat;
  size_t pat_len;
  const uint8_t *subj;
  size_t subj_len;
} fuzz_input;

static int fuzz_split(const uint8_t *data, size_t size, fuzz_input *in)
{
  if (size < 4)
    return -1;
  in->cflags = data[0] & (REG_EXTENDED | REG_ICASE | REG_NEWLINE | REG_NOSUB | REG_LITERAL
                          | REG_RIGHT_ASSOC | REG_UNGREEDY);
  in->eflags = data[1] & (REG_NOTBOL | REG_NOTEOL | REG_APPROX_MATCHER | REG_BACKTRACKING_MATCHER);
  tre_regaparams_default(&in->params);
  in->params.max_cost = data[1] >> 4;
  in->params.cost_ins = in->params.cost_del = in->params.cost_subst = 1;
  size_t plen = (size_t)data[2] | ((size_t)data[3] << 8);
  data += 4;
  size -= 4;
  if (plen > size)
    plen = size;
  in->pat = data;
  in->pat_len = plen;
  in->subj = data + plen;
  in->subj_len = size - plen;
  return 0;
}

static void fuzz_set_locale(void)
{
  /* tre_regncomp/tre_regnexec decode multibyte input with mbrtowc() under the current locale. */
  if (!setlocale(LC_ALL, "C.UTF-8"))
    setlocale(LC_ALL, "C.utf8");
}

#endif
