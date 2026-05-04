#define _GNU_SOURCE  /* strptime */

/*
 * pidwatch - Managed long-running process tied to a pidfile
 *
 * Usage: pidwatch start <pidfile> <timeout> [-o stdout.log] [-e stderr.log] <cmd...>
 *        pidwatch stop <pidfile>
 *        pidwatch status <pidfile>
 *
 * start: Forks cmd into a new session. The parent becomes a watchdog that:
 *   - Removes pidfile if process dies
 *   - Kills process if pidfile is removed (e.g. make clean)
 *   - Kills process after timeout seconds
 *   - Handles TERM/HUP/INT/QUIT for clean shutdown
 *   - Kills the entire session (all descendants) on shutdown,
 *     with SIGTERM then SIGKILL for stragglers
 *
 * stop: Reads pidfile, kills watchdog and its entire session, removes pidfile.
 *
 * status: Reads pidfile, checks if the watchdog + service are alive, prints
 *   a human-readable summary of command, logs, uptime, and state.
 *
 * Pidfile format (extended):
 *   line 0: token         unique instance identifier
 *   line 1: watchdog PID  session leader
 *   line 2: service PID   the actual daemon
 *   line 3: cmd=<command> the full command that was run
 *   line 4: stdout=<path> where stdout goes (or /dev/null)
 *   line 5: stderr=<path> where stderr goes (or /dev/null)
 *   line 6: started=<ts>  ISO 8601 start timestamp
 *
 * Lines 0-2 are read by stop/own_pidfile (backward compatible with the
 * old 3-line format). Lines 3+ are metadata for status/humans. Looking
 * at the pidfile tells you everything about the running process.
 *
 * Log redirection (-o/-e): if specified, the service's stdout/stderr are
 * redirected to the given file paths (append mode) instead of /dev/null.
 * This happens inside the forked child BEFORE exec, so the daemon's
 * output goes to the log even though the watchdog itself is detached.
 */

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t got_signal = 0;

static void on_signal(int sig) {
    (void)sig;
    got_signal = 1;
}

static int read_pidfile_line(const char *path, int line, char *buf, int len) {
    FILE *f = fopen(path, "r");
    if (!f) return -1;
    for (int i = 0; i <= line; i++) {
        if (!fgets(buf, len, f)) { fclose(f); return -1; }
    }
    fclose(f);
    buf[strcspn(buf, "\n")] = 0;
    return 0;
}

static int own_pidfile(const char *path, const char *token) {
    char buf[128];
    if (read_pidfile_line(path, 0, buf, sizeof(buf)) != 0) return 0;
    return strcmp(buf, token) == 0;
}

/*
 * Kill all processes in a session: SIGTERM, wait up to 1s, SIGKILL survivors.
 * sid is the session leader PID (= the watchdog PID).
 */
static void kill_session(pid_t sid) {
    if (sid <= 0) return;

    /* SIGTERM the whole session */
    kill(-sid, SIGTERM);

    /* Wait up to 1s for everyone to exit */
    for (int i = 0; i < 10; i++) {
        usleep(100000);
        if (kill(-sid, 0) != 0) return; /* all dead */
    }

    /* SIGKILL stragglers */
    kill(-sid, SIGKILL);

    /* Brief wait for kernel cleanup */
    for (int i = 0; i < 5; i++) {
        usleep(100000);
        if (kill(-sid, 0) != 0) return;
    }
}

/*
 * Kill the entire session from inside the session (watchdog is session leader).
 * Kills all children first, then the watchdog exits normally.
 */
static void kill_own_session(void) {
    pid_t sid = getsid(0);
    if (sid <= 0) return;

    /* Block signals so we don't kill ourselves mid-cleanup */
    sigset_t block;
    sigfillset(&block);
    sigprocmask(SIG_BLOCK, &block, NULL);

    /* SIGTERM all other processes in session */
    kill(-sid, SIGTERM);

    /* Reap children */
    for (int i = 0; i < 10; i++) {
        usleep(100000);
        int status;
        while (waitpid(-1, &status, WNOHANG) > 0) {}
        /* Check if any children remain */
        if (waitpid(-1, &status, WNOHANG) < 0 && errno == ECHILD) return;
    }

    /* SIGKILL stragglers */
    kill(-sid, SIGKILL);
    while (waitpid(-1, NULL, 0) > 0) {}
}

/* Stop: kill the watchdog's entire session, remove pidfile, wait. */
static int do_stop(const char *pidfile) {
    struct stat st;
    if (stat(pidfile, &st) != 0) return 0;

    char wdbuf[32];
    pid_t wd = 0;
    if (read_pidfile_line(pidfile, 1, wdbuf, sizeof(wdbuf)) == 0) wd = atoi(wdbuf);

    unlink(pidfile);

    if (wd > 0) {
        /* The watchdog is the session leader — kill its entire session */
        kill_session(wd);
    }
    return 0;
}

/* Status: read pidfile, check if processes are alive, print summary. */
static int do_status(const char *pidfile) {
    struct stat st;
    if (stat(pidfile, &st) != 0) {
        printf("  state: not running (no pidfile)\n");
        return 1;
    }

    /* Read all metadata from the pidfile */
    FILE *f = fopen(pidfile, "r");
    if (!f) {
        printf("  state: error (cannot read pidfile)\n");
        return 1;
    }

    char line[4096];
    char token[128] = {0}, cmd[4096] = {0};
    char stdout_path[1024] = {0}, stderr_path[1024] = {0};
    char started[64] = {0};
    pid_t wd = 0, svc = 0;
    int lineno = 0;

    while (fgets(line, sizeof(line), f)) {
        line[strcspn(line, "\n")] = 0;
        switch (lineno) {
            case 0: strncpy(token, line, sizeof(token) - 1); break;
            case 1: wd = atoi(line); break;
            case 2: svc = atoi(line); break;
            default:
                if (strncmp(line, "cmd=", 4) == 0)
                    strncpy(cmd, line + 4, sizeof(cmd) - 1);
                else if (strncmp(line, "stdout=", 7) == 0)
                    strncpy(stdout_path, line + 7, sizeof(stdout_path) - 1);
                else if (strncmp(line, "stderr=", 7) == 0)
                    strncpy(stderr_path, line + 7, sizeof(stderr_path) - 1);
                else if (strncmp(line, "started=", 8) == 0)
                    strncpy(started, line + 8, sizeof(started) - 1);
                break;
        }
        lineno++;
    }
    fclose(f);

    /* Check if processes are alive */
    int wd_alive = (wd > 0 && kill(wd, 0) == 0);
    int svc_alive = (svc > 0 && kill(svc, 0) == 0);

    if (svc_alive) {
        printf("  state:   running (pid %d, watchdog %d)\n", svc, wd);
    } else if (wd_alive) {
        printf("  state:   watchdog alive but service dead (pid %d, wd %d)\n", svc, wd);
    } else {
        printf("  state:   dead (stale pidfile)\n");
    }

    if (cmd[0])          printf("  cmd:     %s\n", cmd);
    if (started[0])      printf("  started: %s\n", started);

    /* Uptime */
    if (started[0] && svc_alive) {
        struct tm tm = {0};
        if (strptime(started, "%Y-%m-%dT%H:%M:%S", &tm)) {
            time_t start_t = mktime(&tm);
            time_t now = time(NULL);
            long secs = (long)(now - start_t);
            if (secs > 0) {
                long h = secs / 3600, m = (secs % 3600) / 60, s = secs % 60;
                printf("  uptime:  %ldh %ldm %lds\n", h, m, s);
            }
        }
    }

    if (stdout_path[0]) {
        struct stat ls;
        long sz = (stat(stdout_path, &ls) == 0) ? ls.st_size : -1;
        if (sz >= 0)
            printf("  stdout:  %s (%ldB)\n", stdout_path, sz);
        else
            printf("  stdout:  %s\n", stdout_path);
    }
    if (stderr_path[0] && strcmp(stderr_path, stdout_path) != 0) {
        struct stat ls;
        long sz = (stat(stderr_path, &ls) == 0) ? ls.st_size : -1;
        if (sz >= 0)
            printf("  stderr:  %s (%ldB)\n", stderr_path, sz);
        else
            printf("  stderr:  %s\n", stderr_path);
    }

    return svc_alive ? 0 : 1;
}

/*
 * Redirect an fd to a file (append mode). Returns 0 on success.
 * If path is NULL, redirects to /dev/null.
 */
static int redirect_fd(int fd, const char *path) {
    int target;
    if (path) {
        target = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    } else {
        target = open("/dev/null", O_RDWR);
    }
    if (target < 0) return -1;
    dup2(target, fd);
    if (target > 2) close(target);
    return 0;
}

static int do_start(const char *pidfile, int timeout,
                    const char *stdout_log, const char *stderr_log,
                    int cmd_argc, char **cmd) {
    do_stop(pidfile);

    /* Fork the watchdog into its own session */
    pid_t outer = fork();
    if (outer < 0) { perror("fork"); return 1; }
    if (outer > 0) return 0;
    setsid();

    /* Fork the service process */
    pid_t svc = fork();
    if (svc < 0) { perror("fork"); _exit(1); }
    if (svc == 0) {
        /* Redirect stdin to /dev/null always */
        redirect_fd(0, NULL);
        /* Redirect stdout and stderr to log files or /dev/null */
        redirect_fd(1, stdout_log);
        redirect_fd(2, stderr_log);

        execvp(cmd[0], cmd);
        _exit(127);
    }

    /* Generate unique token */
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    char token[64];
    snprintf(token, sizeof(token), "%d:%ld%09ld", getpid(), ts.tv_sec, ts.tv_nsec);

    /* Generate start timestamp */
    time_t now = time(NULL);
    struct tm *tm = localtime(&now);
    char started[32];
    strftime(started, sizeof(started), "%Y-%m-%dT%H:%M:%S", tm);

    /* Build command string for the pidfile */
    char cmd_str[4096] = {0};
    int pos = 0;
    for (int i = 0; i < cmd_argc && pos < (int)sizeof(cmd_str) - 1; i++) {
        if (i > 0) cmd_str[pos++] = ' ';
        int n = snprintf(cmd_str + pos, sizeof(cmd_str) - pos, "%s", cmd[i]);
        if (n > 0) pos += n;
    }

    /* Write extended pidfile */
    FILE *f = fopen(pidfile, "w");
    if (!f) { perror("fopen pidfile"); kill_own_session(); _exit(1); }
    fprintf(f, "%s\n%d\n%d\n", token, getpid(), svc);
    fprintf(f, "cmd=%s\n", cmd_str);
    fprintf(f, "stdout=%s\n", stdout_log ? stdout_log : "/dev/null");
    fprintf(f, "stderr=%s\n", stderr_log ? stderr_log : "/dev/null");
    fprintf(f, "started=%s\n", started);
    fclose(f);

    /* Install signal handlers */
    struct sigaction sa = { .sa_handler = on_signal, .sa_flags = 0 };
    sigemptyset(&sa.sa_mask);
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGHUP, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGQUIT, &sa, NULL);

    /* Watchdog loop */
    int elapsed = 0;
    while (1) {
        sleep(1);

        if (got_signal) {
            if (own_pidfile(pidfile, token)) unlink(pidfile);
            kill_own_session();
            _exit(0);
        }

        /* Service died? Clean up entire session in case of orphaned children */
        if (waitpid(svc, NULL, WNOHANG) != 0) {
            if (own_pidfile(pidfile, token)) unlink(pidfile);
            kill_own_session();
            _exit(0);
        }

        /* Pidfile gone or taken over? */
        if (!own_pidfile(pidfile, token)) {
            kill_own_session();
            _exit(0);
        }

        /* Timeout? */
        elapsed++;
        if (elapsed >= timeout) {
            if (own_pidfile(pidfile, token)) unlink(pidfile);
            kill_own_session();
            _exit(0);
        }
    }
}

int main(int argc, char **argv) {
    if (argc < 3) goto usage;

    if (strcmp(argv[1], "stop") == 0) {
        return do_stop(argv[2]);
    }

    if (strcmp(argv[1], "status") == 0) {
        return do_status(argv[2]);
    }

    if (strcmp(argv[1], "start") == 0) {
        if (argc < 5) goto usage;
        int timeout = atoi(argv[3]);
        if (timeout <= 0) { fprintf(stderr, "invalid timeout: %s\n", argv[3]); return 1; }

        /* Parse optional -o/-e flags before the command */
        const char *stdout_log = NULL;
        const char *stderr_log = NULL;
        int cmd_start = 4;

        while (cmd_start < argc) {
            if (strcmp(argv[cmd_start], "-o") == 0 && cmd_start + 1 < argc) {
                stdout_log = argv[cmd_start + 1];
                cmd_start += 2;
            } else if (strcmp(argv[cmd_start], "-e") == 0 && cmd_start + 1 < argc) {
                stderr_log = argv[cmd_start + 1];
                cmd_start += 2;
            } else {
                break; /* rest is the command */
            }
        }

        if (cmd_start >= argc) goto usage;
        return do_start(argv[2], timeout, stdout_log, stderr_log,
                        argc - cmd_start, &argv[cmd_start]);
    }

usage:
    fprintf(stderr,
        "Usage: %s start <pidfile> <timeout> [-o stdout.log] [-e stderr.log] <cmd...>\n"
        "       %s stop <pidfile>\n"
        "       %s status <pidfile>\n",
        argv[0], argv[0], argv[0]);
    return 1;
}
