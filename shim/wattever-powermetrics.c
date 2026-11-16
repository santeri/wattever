#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/event.h>
#include <sys/wait.h>
#include <unistd.h>

// Fixed command. The caller cannot pass arguments or an environment.
// Once this process is root, the menu bar app can no longer signal it, so it
// watches that app and stops powermetrics when the app exits.

static volatile sig_atomic_t stop = 0;
static pid_t child_pid = -1;

static void on_stop(int sig) {
  (void)sig;
  stop = 1;
  if (child_pid > 0) {
    kill(child_pid, SIGTERM);
  }
}

static void become_root(void) {
#if !defined(WATTEVER_HELPER_TEST)
  if (geteuid() != 0 || setgid(0) != 0 || setuid(0) != 0) {
    fprintf(stderr, "wattever-powermetrics: not setuid root\n");
    _exit(1);
  }
#else
  (void)0;
#endif
}

static void redirect_to_null(void) {
  int fd = open("/dev/null", O_RDWR);
  if (fd < 0) {
    return;
  }
  dup2(fd, STDIN_FILENO);
  dup2(fd, STDOUT_FILENO);
  dup2(fd, STDERR_FILENO);
  if (fd > STDERR_FILENO) {
    close(fd);
  }
  int maxfd = (int)sysconf(_SC_OPEN_MAX);
  if (maxfd < 0 || maxfd > 1024) {
    maxfd = 1024;
  }
  for (int extra = STDERR_FILENO + 1; extra < maxfd; extra++) {
    close(extra);
  }
}

static pid_t spawn_sampler(void) {
  pid_t child = fork();
  if (child < 0) {
    _exit(1);
  }
  if (child == 0) {
    redirect_to_null();
    setpgid(0, 0);
#if defined(WATTEVER_HELPER_TEST)
    char *argv[] = {"sleep", "30", NULL};
    char *envp[] = {"PATH=/usr/bin:/bin", NULL};
    execve("/bin/sleep", argv, envp);
#else
    char *argv[] = {
        "powermetrics", "--samplers", "cpu_power,gpu_power", "-i", "1000", "-n", "-1", NULL,
    };
    char *envp[] = {"PATH=/usr/bin:/bin", NULL};
    execve("/usr/bin/powermetrics", argv, envp);
#endif
    _exit(127);
  }
  setpgid(child, child);
  return child;
}

static void reap(pid_t child) {
  kill(child, SIGTERM);
  for (int attempt = 0; attempt < 20; attempt++) {
    if (waitpid(child, NULL, WNOHANG) == child) {
      return;
    }
    usleep(50000);
  }
  kill(child, SIGKILL);
  waitpid(child, NULL, 0);
}

int main(void) {
  become_root();

  struct sigaction action;
  memset(&action, 0, sizeof action);
  action.sa_handler = on_stop;
  sigaction(SIGTERM, &action, NULL);
  sigaction(SIGINT, &action, NULL);

  pid_t parent = getppid();
  pid_t child = spawn_sampler();
  child_pid = child;

  int queue = kqueue();
  if (queue < 0) {
    reap(child);
    return 1;
  }
  struct kevent changes[2];
  EV_SET(&changes[0], parent, EVFILT_PROC, EV_ADD, NOTE_EXIT, 0, NULL);
  EV_SET(&changes[1], child, EVFILT_PROC, EV_ADD, NOTE_EXIT, 0, NULL);
  if (kevent(queue, changes, 2, NULL, 0, NULL) < 0) {
    reap(child);
    return 1;
  }

  while (!stop) {
    struct kevent event;
    int got = kevent(queue, NULL, 0, &event, 1, NULL);
    if (got < 0 && errno == EINTR) {
      continue;
    }
    (void)event.ident;
    break;
  }
  reap(child);
  return 0;
}
