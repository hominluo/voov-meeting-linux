/* LD_PRELOAD net tracer: logs getaddrinfo + connect targets to $WEMEET_NETLOG */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <dlfcn.h>
#include <netdb.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <pthread.h>

static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;

static void logline(const char *fmt, ...)
{
    const char *path = getenv("WEMEET_NETLOG");
    if (!path) return;
    FILE *f = fopen(path, "a");
    if (!f) return;
    va_list ap;
    pthread_mutex_lock(&mu);
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fputc('\n', f);
    pthread_mutex_unlock(&mu);
    fclose(f);
}

int getaddrinfo(const char *node, const char *service,
                const struct addrinfo *hints, struct addrinfo **res)
{
    static int (*real)(const char *, const char *, const struct addrinfo *, struct addrinfo **);
    if (!real) real = dlsym(RTLD_NEXT, "getaddrinfo");
    int r = real(node, service, hints, res);
    logline("getaddrinfo node=%s service=%s -> %d", node ? node : "(null)", service ? service : "(null)", r);
    return r;
}

struct hostent *gethostbyname(const char *name)
{
    static struct hostent *(*real)(const char *);
    if (!real) real = dlsym(RTLD_NEXT, "gethostbyname");
    logline("gethostbyname name=%s", name ? name : "(null)");
    return real(name);
}

int connect(int fd, const struct sockaddr *addr, socklen_t len)
{
    static int (*real)(int, const struct sockaddr *, socklen_t);
    if (!real) real = dlsym(RTLD_NEXT, "connect");
    char ip[INET6_ADDRSTRLEN] = {0};
    int port = 0;
    if (addr->sa_family == AF_INET) {
        inet_ntop(AF_INET, &((struct sockaddr_in *)addr)->sin_addr, ip, sizeof ip);
        port = ntohs(((struct sockaddr_in *)addr)->sin_port);
    } else if (addr->sa_family == AF_INET6) {
        inet_ntop(AF_INET6, &((struct sockaddr_in6 *)addr)->sin6_addr, ip, sizeof ip);
        port = ntohs(((struct sockaddr_in6 *)addr)->sin6_port);
    } else {
        return real(fd, addr, len);
    }
    logline("connect fd=%d %s:%d", fd, ip, port);
    return real(fd, addr, len);
}