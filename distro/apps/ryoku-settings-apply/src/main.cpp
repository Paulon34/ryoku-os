/*
 * ryoku-settings-apply — privileged helper for Ryoku Settings on Debian Modular.
 *
 * Allowlisted operations only:
 *   ryoku-settings-apply apply
 *   ryoku-settings-apply rollback
 *   ryoku-settings-apply switch-generation <N>
 *
 * Repo flake dir, host attr, and desktop user are compile-time constants.
 * The GUI never supplies repo/host/command strings — only an allowlisted
 * operation token and, for switch-generation, a strict integer.
 *
 * Debian adaptation vs NixOS:
 *   - apply/rollback use `home-manager switch` (not nixos-rebuild)
 *   - generations are per-user home-manager-* links (not system-*)
 *   - runs as the desktop user via runuser when invoked through pkexec
 *
 * No shell. No system(). fork + execv + waitpid only.
 */

#include "ops.h"

#include <errno.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef RYOKU_REPO_PATH
#error "RYOKU_REPO_PATH must be defined at compile time"
#endif

#ifndef RYOKU_FLAKE_HOST
#error "RYOKU_FLAKE_HOST must be defined at compile time"
#endif

#ifndef RYOKU_FLAKE_DIR
#error "RYOKU_FLAKE_DIR must be defined at compile time"
#endif

#ifndef RYOKU_HOME_MANAGER
#error "RYOKU_HOME_MANAGER must be defined at compile time"
#endif

#ifndef RYOKU_NIX_ENV
#error "RYOKU_NIX_ENV must be defined at compile time"
#endif

#ifndef RYOKU_RUNUSER
#error "RYOKU_RUNUSER must be defined at compile time"
#endif

#ifndef RYOKU_DBUS_RUN_SESSION
#error "RYOKU_DBUS_RUN_SESSION must be defined at compile time"
#endif

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

static void usage(void)
{
    fprintf(stderr,
            "usage: ryoku-settings-apply {apply|rollback|switch-generation <N>}\n"
            "\n"
            "Privileged Ryoku Settings helper (Debian Modular / Home Manager).\n"
            "Repo, flake dir, and host are fixed at build time.\n"
            "switch-generation accepts only a positive decimal generation number.\n");
}

static int run_execv_wait(const char *path, char *const argv[])
{
    const pid_t pid = fork();
    if (pid < 0) {
        fprintf(stderr, "ryoku-settings-apply: fork failed: %s\n", strerror(errno));
        return 2;
    }
    if (pid == 0) {
        execv(path, argv);
        fprintf(stderr, "ryoku-settings-apply: execv(%s) failed: %s\n", path, strerror(errno));
        _exit(127);
    }

    int status = 0;
    if (waitpid(pid, &status, 0) < 0) {
        fprintf(stderr, "ryoku-settings-apply: waitpid failed: %s\n", strerror(errno));
        return 2;
    }
    if (WIFEXITED(status))
        return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) {
        fprintf(stderr, "ryoku-settings-apply: child killed by signal %d\n", WTERMSIG(status));
        return 2;
    }
    return 2;
}

static const char *desktop_user(void)
{
    return RYOKU_FLAKE_HOST; /* host attr == desktop username on Debian Modular */
}

static int profile_path(char *buf, size_t buflen)
{
    const int n = snprintf(buf, buflen, "/nix/var/nix/profiles/per-user/%s/home-manager",
                           desktop_user());
    if (n < 0 || (size_t)n >= buflen)
        return -1;
    return 0;
}

static int profile_points_to_generation(unsigned gen)
{
    char expected[64];
    if (snprintf(expected, sizeof(expected), "home-manager-%u-link", gen) >= (int)sizeof(expected))
        return 0;
    char profile[PATH_MAX];
    if (profile_path(profile, sizeof(profile)) != 0)
        return 0;
    char buf[PATH_MAX];
    const ssize_t n = readlink(profile, buf, sizeof(buf) - 1);
    if (n < 0)
        return 0;
    buf[n] = '\0';
    if (strcmp(buf, expected) == 0)
        return 1;
    const size_t elen = strlen(expected);
    const size_t blen = strlen(buf);
    if (blen >= elen && strcmp(buf + (blen - elen), expected) == 0) {
        if (blen == elen || buf[blen - elen - 1] == '/')
            return 1;
    }
    return 0;
}

/* Build flake ref: <absolute flake dir>#<host> */
static int flake_ref(char *out, size_t outlen)
{
    const int n = snprintf(out, outlen, "%s#%s", RYOKU_FLAKE_DIR, RYOKU_FLAKE_HOST);
    if (n < 0 || (size_t)n >= outlen)
        return -1;
    return 0;
}

/* runuser -u USER -- dbus-run-session -- home-manager <args...> */
static int run_hm_as_user(char *const hm_argv[])
{
    /* Count hm args */
    int hm_count = 0;
    while (hm_argv[hm_count] != NULL)
        ++hm_count;

    /* runuser -u USER -- dbus-run-session -- home-manager ... */
    const int total = 6 + hm_count; /* runuser -u user -- dbus -- hm + args + NULL already in hm */
    char **argv = (char **)calloc((size_t)total + 1, sizeof(char *));
    if (!argv) {
        fprintf(stderr, "ryoku-settings-apply: OOM\n");
        return 2;
    }
    int i = 0;
    argv[i++] = (char *)"runuser";
    argv[i++] = (char *)"-u";
    argv[i++] = (char *)desktop_user();
    argv[i++] = (char *)"--";
    argv[i++] = (char *)"dbus-run-session";
    argv[i++] = (char *)"--";
    for (int j = 0; j < hm_count; ++j)
        argv[i++] = hm_argv[j];
    argv[i] = NULL;

    const int rc = run_execv_wait(RYOKU_RUNUSER, argv);
    free(argv);
    return rc;
}

static int do_apply(void)
{
    char ref[4096];
    if (flake_ref(ref, sizeof(ref)) != 0) {
        fprintf(stderr, "ryoku-settings-apply: flake ref too long\n");
        return 2;
    }
    fprintf(stderr, "ryoku-settings-apply: home-manager switch --flake %s\n", ref);
    char *const hm_args[] = {
        (char *)"home-manager",
        (char *)"switch",
        (char *)"--flake",
        ref,
        NULL,
    };
    /* When already the desktop user, skip runuser. */
    const uid_t uid = getuid();
    struct passwd *pw = getpwnam(desktop_user());
    if (pw && pw->pw_uid == uid) {
        char *const dbus_args[] = {
            (char *)"dbus-run-session",
            (char *)"--",
            (char *)"home-manager",
            (char *)"switch",
            (char *)"--flake",
            ref,
            NULL,
        };
        return run_execv_wait(RYOKU_DBUS_RUN_SESSION, dbus_args);
    }
    return run_hm_as_user(hm_args);
}

static int do_rollback(void)
{
    fprintf(stderr, "ryoku-settings-apply: home-manager switch --rollback\n");
    char *const hm_args[] = {
        (char *)"home-manager",
        (char *)"switch",
        (char *)"--rollback",
        NULL,
    };
    const uid_t uid = getuid();
    struct passwd *pw = getpwnam(desktop_user());
    if (pw && pw->pw_uid == uid) {
        char *const dbus_args[] = {
            (char *)"dbus-run-session",
            (char *)"--",
            (char *)"home-manager",
            (char *)"switch",
            (char *)"--rollback",
            NULL,
        };
        return run_execv_wait(RYOKU_DBUS_RUN_SESSION, dbus_args);
    }
    return run_hm_as_user(hm_args);
}

static int do_switch_generation(unsigned gen)
{
    char err[512];
    char canon[PATH_MAX];
    if (ryoku_validate_hm_generation(desktop_user(), gen, canon, sizeof(canon), err, sizeof(err)) != 0) {
        fprintf(stderr, "ryoku-settings-apply: %s\n", err);
        return 3;
    }

    char genstr[32];
    if (snprintf(genstr, sizeof(genstr), "%u", gen) >= (int)sizeof(genstr)) {
        fprintf(stderr, "ryoku-settings-apply: generation string overflow\n");
        return 2;
    }

    char profile[PATH_MAX];
    if (profile_path(profile, sizeof(profile)) != 0) {
        fprintf(stderr, "ryoku-settings-apply: profile path overflow\n");
        return 2;
    }

    fprintf(stderr, "ryoku-settings-apply: switching HM profile to generation %u\n", gen);
    fprintf(stderr, "ryoku-settings-apply: target %s\n", canon);

    char *const env_args[] = {
        (char *)"nix-env",
        (char *)"--profile",
        profile,
        (char *)"--switch-generation",
        genstr,
        NULL,
    };
    const int env_rc = run_execv_wait(RYOKU_NIX_ENV, env_args);
    if (env_rc != 0) {
        fprintf(stderr, "ryoku-settings-apply: nix-env --switch-generation failed (exit %d)\n", env_rc);
        return env_rc;
    }

    if (!profile_points_to_generation(gen)) {
        fprintf(stderr,
                "ryoku-settings-apply: after nix-env, HM profile does not point to "
                "generation %u — aborting activation\n",
                gen);
        return 4;
    }

    /*
     * Activate the chosen generation's own activate script.
     * Do NOT call do_apply() / home-manager switch --flake here — that rebuilds
     * from current source and would discard the selected older generation.
     */
    char activate[PATH_MAX];
    if (snprintf(activate, sizeof(activate), "%s/activate", canon) >= (int)sizeof(activate)) {
        fprintf(stderr, "ryoku-settings-apply: activate path overflow\n");
        return 2;
    }
    if (access(activate, X_OK) != 0) {
        fprintf(stderr,
                "ryoku-settings-apply: generation %u has no executable activate at %s\n",
                gen, activate);
        return 3;
    }

    fprintf(stderr, "ryoku-settings-apply: activating via %s\n", activate);
    char *const act_args[] = {
        activate,
        NULL,
    };
    const uid_t uid = getuid();
    struct passwd *pw = getpwnam(desktop_user());
    if (pw && pw->pw_uid == uid) {
        execv(activate, act_args);
        fprintf(stderr, "ryoku-settings-apply: execv(%s) failed: %s\n", activate, strerror(errno));
        return 2;
    }

    /* pkexec path: run activate as the desktop user. */
    char *const run_args[] = {
        (char *)"runuser",
        (char *)"-u",
        (char *)desktop_user(),
        (char *)"--",
        activate,
        NULL,
    };
    return run_execv_wait(RYOKU_RUNUSER, run_args);
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        usage();
        return 1;
    }

    const int op = ryoku_parse_operation(argv[1]);
    if (op == RYOKU_APPLY_OP_INVALID) {
        fprintf(stderr, "ryoku-settings-apply: invalid operation '%s'\n", argv[1]);
        usage();
        return 1;
    }

    if (op == RYOKU_APPLY_OP_SWITCH_GENERATION) {
        if (argc != 3) {
            fprintf(stderr, "ryoku-settings-apply: switch-generation requires exactly one number\n");
            usage();
            return 1;
        }
        unsigned gen = 0;
        if (ryoku_parse_generation_number(argv[2], &gen) != 0) {
            fprintf(stderr, "ryoku-settings-apply: invalid generation number '%s'\n", argv[2]);
            return 1;
        }
        return do_switch_generation(gen);
    }

    if (argc != 2) {
        usage();
        return 1;
    }

    if (op == RYOKU_APPLY_OP_APPLY)
        return do_apply();
    return do_rollback();
}
