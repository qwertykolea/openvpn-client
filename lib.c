#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

typedef enum {
  OBFS_DISABLED = 0,
  OBFS_PRE_HANDSHAKE_NOISE = 1,
  OBFS_POST_HANDSHAKE_JUNK = 2
} obfs_mode_t;

static ssize_t (*real_sendto)(int, const void *, size_t, int,
                              const struct sockaddr *, socklen_t) = NULL;

static obfs_mode_t fetch_obfs_mode(void) {
  const char *env = getenv("OBFUSCATE");
  return env ? (obfs_mode_t)atoi(env) : OBFS_DISABLED;
}

static inline int is_control_packet(const uint8_t *payload) {
  uint8_t op = payload[0] >> 3;
  return (op == 7 || op == 8 || op == 10);
}

static void inject_dummy_stream(int fd, const void *orig_buf, size_t orig_len,
                                int flags, const struct sockaddr *dst,
                                socklen_t addrlen, obfs_mode_t mode) {
  srand((unsigned int)(time(NULL) ^ getpid()));

  for (int cycle = 0; cycle < 2; cycle++) {
    size_t packet_size = orig_len + (size_t)(rand() % 101);
    uint8_t *buffer = (uint8_t *)malloc(packet_size);
    if (!buffer)
      continue;

    if (mode == OBFS_PRE_HANDSHAKE_NOISE) {
      uint8_t first_byte;
      do {
        first_byte = (uint8_t)(rand() % 256);
      } while ((first_byte >> 3) >= 1 && (first_byte >> 3) <= 11);

      buffer[0] = first_byte;
      for (size_t i = 1; i < packet_size; i++) {
        buffer[i] = (uint8_t)(rand() % 256);
      }
    } else {
      memcpy(buffer, orig_buf, orig_len);
      buffer[0] = 40; // Malformed opcode
      for (size_t i = orig_len; i < packet_size; i++) {
        buffer[i] = (uint8_t)(rand() % 256);
      }
    }

    int send_count = 100 + (rand() % 101);
    for (int i = 0; i < send_count; i++) {
      real_sendto(fd, buffer, packet_size, flags, dst, addrlen);
    }
    free(buffer);
  }
}

ssize_t sendto(int sockfd, const void *buf, size_t len, int flags,
               const struct sockaddr *dest_addr, socklen_t addrlen) {
  if (!real_sendto) {
    real_sendto =
        (ssize_t (*)(int, const void *, size_t, int, const struct sockaddr *,
                     socklen_t))dlsym(RTLD_NEXT, "sendto");
  }

  obfs_mode_t mode = fetch_obfs_mode();
  if (mode == OBFS_DISABLED || !buf || len == 0) {
    return real_sendto(sockfd, buf, len, flags, dest_addr, addrlen);
  }

  if (is_control_packet((const uint8_t *)buf)) {
    ssize_t res = 0;
    if (mode == OBFS_POST_HANDSHAKE_JUNK) {
      res = real_sendto(sockfd, buf, len, flags, dest_addr, addrlen);
      usleep(100000);
    }

    inject_dummy_stream(sockfd, buf, len, flags, dest_addr, addrlen, mode);

    if (mode == OBFS_POST_HANDSHAKE_JUNK) {
      return res;
    }
    usleep(100000);
  }

  return real_sendto(sockfd, buf, len, flags, dest_addr, addrlen);
}
