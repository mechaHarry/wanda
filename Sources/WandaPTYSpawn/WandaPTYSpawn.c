#include "WandaPTYSpawn.h"

#include <sys/ioctl.h>
#include <unistd.h>

pid_t wanda_pty_fork_exec(
    int master_fd,
    int slave_fd,
    const char *executable,
    char *const argv[],
    char *const envp[]
) {
    pid_t pid = fork();
    if (pid != 0) {
        return pid;
    }

    close(master_fd);

    if (setsid() < 0) {
        _exit(127);
    }

    if (ioctl(slave_fd, TIOCSCTTY, 0) < 0) {
        _exit(127);
    }

    if (dup2(slave_fd, STDIN_FILENO) < 0) {
        _exit(127);
    }

    if (dup2(slave_fd, STDOUT_FILENO) < 0) {
        _exit(127);
    }

    if (dup2(slave_fd, STDERR_FILENO) < 0) {
        _exit(127);
    }

    if (slave_fd > STDERR_FILENO) {
        close(slave_fd);
    }

    execve(executable, argv, envp);
    _exit(127);
}
