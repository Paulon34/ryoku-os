#define _DEFAULT_SOURCE
#define _POSIX_C_SOURCE 200809L

#include "ops.h"

#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

int ryoku_parse_operation(const char *arg)
{
    if (!arg)
        return RYOKU_APPLY_OP_INVALID;
    if (strcmp(arg, "apply") == 0)
        return RYOKU_APPLY_OP_APPLY;
    if (strcmp(arg, "rollback") == 0)
        return RYOKU_APPLY_OP_ROLLBACK;
    if (strcmp(arg, "switch-generation") == 0)
        return RYOKU_APPLY_OP_SWITCH_GENERATION;
    return RYOKU_APPLY_OP_INVALID;
}

int ryoku_parse_generation_number(const char *arg, unsigned *out)
{
    if (!arg || !out || !*arg)
        return -1;
    for (const char *p = arg; *p; ++p) {
        if (!isdigit((unsigned char)*p))
            return -1;
    }
    if (arg[0] == '0')
        return -1;

    errno = 0;
    char *end = NULL;
    unsigned long v = strtoul(arg, &end, 10);
    if (errno != 0 || end == arg || (end && *end != '\0'))
        return -1;
    if (v < 1UL || v > 1000000UL)
        return -1;
    *out = (unsigned)v;
    return 0;
}

int ryoku_hm_generation_link_path(const char *user, unsigned gen, char *buf, size_t buflen)
{
    if (!user || !*user || !buf || buflen < 64)
        return -1;
    /* Desktop username only: [a-z_][a-z0-9_-]* */
    for (const char *p = user; *p; ++p) {
        const unsigned char c = (unsigned char)*p;
        if (!(isalnum(c) || c == '_' || c == '-'))
            return -1;
    }
    const int n = snprintf(buf, buflen,
                           "/nix/var/nix/profiles/per-user/%s/home-manager-%u-link",
                           user, gen);
    if (n < 0 || (size_t)n >= buflen)
        return -1;
    return 0;
}

static int set_err(char *err_out, size_t err_len, const char *msg)
{
    if (err_out && err_len > 0)
        snprintf(err_out, err_len, "%s", msg ? msg : "validation failed");
    return -1;
}

int ryoku_validate_hm_generation(const char *user, unsigned gen,
                                 char *canon_out, size_t canon_len,
                                 char *err_out, size_t err_len)
{
    if (gen < 1)
        return set_err(err_out, err_len, "generation must be >= 1");

    char linkpath[PATH_MAX];
    if (ryoku_hm_generation_link_path(user, gen, linkpath, sizeof(linkpath)) != 0)
        return set_err(err_out, err_len, "cannot format HM generation link path");

    struct stat st;
    if (lstat(linkpath, &st) != 0)
        return set_err(err_out, err_len, "HM generation link does not exist");
    if (!S_ISLNK(st.st_mode))
        return set_err(err_out, err_len, "HM generation path is not a symlink");

    char resolved[PATH_MAX];
    if (!realpath(linkpath, resolved))
        return set_err(err_out, err_len, "cannot canonicalize HM generation link");

    if (strncmp(resolved, "/nix/store/", 11) != 0)
        return set_err(err_out, err_len, "HM generation target is not in /nix/store");

    if (canon_out && canon_len > 0) {
        if (strlen(resolved) + 1 > canon_len)
            return set_err(err_out, err_len, "canonical path buffer too small");
        memcpy(canon_out, resolved, strlen(resolved) + 1);
    }
    return 0;
}
