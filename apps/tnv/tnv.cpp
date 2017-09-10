#include "tnv.h"
#include <stdlib.h> /* for exit() */

int readChannel(unsigned chn) {
  const int BUF_SIZE = 256;
  char buffer[BUF_SIZE];
  snprintf(buffer,BUF_SIZE,
	   "/sys/bus/iio/devices/iio:device0/in_voltage%d_raw",chn);
  FILE * f = fopen(buffer, "r");
  if (!f) {
    perror(buffer);
    exit(1);
  }
  int count;
  int read = fscanf(f,"%d", &count);
  if (read != 1) {
    fprintf(stderr,"Read failure on %s\n",buffer);
    exit(2);
  }
  fclose(f);
  return count;
}

int main() {
  unsigned count = readChannel(1);
  printf("%d = %d C, %f F\n", count, getCentigradeFromCount(count), getFloatFarenheitFromCount(count));
  return 0;
}
