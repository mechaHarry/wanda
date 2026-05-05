#ifndef WANDA_PTY_SPAWN_H
#define WANDA_PTY_SPAWN_H

#include <sys/types.h>

pid_t wanda_pty_fork_exec(
    int master_fd,
    int slave_fd,
    int close_limit,
    const char *executable,
    char *const argv[],
    char *const envp[]
);

#endif
