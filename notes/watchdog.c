#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <linux/watchdog.h>
#include <stdio.h>

int main()
{
  int fd = open("/dev/watchdog", O_WRONLY);
  int timeout = 15;
  ioctl(fd, WDIOC_SETTIMEOUT, &timeout);
  printf("Setting timeout to %d seconds\n", timeout);
  close(fd);
  return 0;
}
