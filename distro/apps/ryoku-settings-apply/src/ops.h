#pragma once

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Allowlisted operations for ryoku-settings-apply (Debian Modular / HM). */
enum RyokuApplyOp {
    RYOKU_APPLY_OP_INVALID = -1,
    RYOKU_APPLY_OP_APPLY = 0,
    RYOKU_APPLY_OP_ROLLBACK = 1,
    RYOKU_APPLY_OP_SWITCH_GENERATION = 2,
};

/* Returns RYOKU_APPLY_OP_* for exact token match; no substrings. */
int ryoku_parse_operation(const char *arg);

/* Strict positive decimal generation number (no signs, spaces, suffixes). */
int ryoku_parse_generation_number(const char *arg, unsigned *out);

/* Writes /nix/var/nix/profiles/per-user/<user>/home-manager-<N>-link into buf. */
int ryoku_hm_generation_link_path(const char *user, unsigned gen, char *buf, size_t buflen);

/* Validate HM generation symlink exists and resolves under /nix/store/. */
int ryoku_validate_hm_generation(const char *user, unsigned gen,
                                 char *canon_out, size_t canon_len,
                                 char *err_out, size_t err_len);

#ifdef __cplusplus
}
#endif
