/*
 * Execs argv[1..] in place, first arranging for the kernel to SIGKILL this
 * process the moment its parent dies.
 *
 * Why this exists: GamesTutor.Go.Engine spawns KataGo via
 * Port.open({:spawn_executable, ...}). Port.close/1 (or the port's owning
 * process simply exiting) only closes the port's pipes -- it relies on
 * KataGo noticing EOF on stdin and exiting itself, which does nothing for a
 * wedged process and is entirely moot if the BEAM is SIGKILLed (no Elixir
 * code runs at all in that case, so nothing can even attempt Port.close).
 * PR_SET_PDEATHSIG makes the kernel itself do the killing, unconditionally,
 * the instant this process's parent (erl_child_setup, which every
 * spawn_executable child is parented to) goes away.
 *
 * Deliberately minimal: no argument parsing beyond argv[1] being the real
 * program, no signal forwarding beyond death -- GamesTutor.Go.Engine
 * handles graceful shutdown itself (it knows the OS pid and sends it a
 * direct kill -9 from terminate/2 before it ever gets to the point where
 * this matters).
 */
#include <sys/prctl.h>
#include <signal.h>
#include <unistd.h>
#include <stdio.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <program> [args...]\n", argv[0]);
        return 1;
    }

    pid_t parent_at_start = getppid();

    if (prctl(PR_SET_PDEATHSIG, SIGKILL) == -1) {
        perror("pdeathsig_wrapper: prctl(PR_SET_PDEATHSIG)");
        return 1;
    }

    /* Close the race between fork and the prctl call above: if the parent
     * already exited in that window, getppid() now returns the id we got
     * reparented to, so PDEATHSIG would never fire for the parent we
     * actually cared about. Refuse to run as an orphan rather than risk it. */
    if (getppid() != parent_at_start) {
        fprintf(stderr, "pdeathsig_wrapper: parent exited before setup completed\n");
        return 1;
    }

    execvp(argv[1], &argv[1]);
    perror("pdeathsig_wrapper: execvp");
    return 1;
}
