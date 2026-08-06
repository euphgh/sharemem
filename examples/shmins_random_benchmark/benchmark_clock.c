#define _POSIX_C_SOURCE 200809L

#include <stdint.h>
#include <time.h>

int64_t shmins_benchmark_monotonic_ns(void) {
    struct timespec timestamp;

    if (clock_gettime(CLOCK_MONOTONIC, &timestamp) != 0) {
        return -1;
    }

    return (int64_t)timestamp.tv_sec * INT64_C(1000000000) + timestamp.tv_nsec;
}
