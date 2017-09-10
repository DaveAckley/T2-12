#include "tnv.h"
#include <stdlib.h> /* for exit() */

/** Circuit for this count is:
 *
 *               200K 0.1%    V0     10K 0.1%
 *     Vgrid o----/\/\/--------o----/\/\/---o GNDA
 *                             |
 *                             |
 *                             o
 *                       AIN0 (chnl 0)
 *                 with count 0->V0=0, count 4095->V0=1.8V
 *
 *
 *   V0 = Vgrid * 10K / ( 200K + 10K )
 *
 *   V0/Vgrid = 10K / 210K
 *
 *   Vgrid/V0 = 210K / 10K        given V0 != 0
 *
 *   Vgrid = V0 * 210K / 10K
 *
 *   Vgrid = (1.8 * count / 4095) * 210K / 10K
 *
 *   Vgrid = (1.8 * 210K ) / (10K * 4095) * count
 *
 *   Vgrid = 378000 / 40950000 * count
 *
 */
float gridVoltage(unsigned count) {
  const float scale = 378000.0 / 40950000.0;
  return count * scale;
}

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
  unsigned ctrcount = readChannel(1);
  unsigned edgecount = readChannel(2);
  unsigned gridvcount = readChannel(0);
  printf("Vgrid = %f V\n", gridVoltage(gridvcount));
  printf("ctrtmp = %d C  (%f F)\n",
	 getCentigradeFromCount(ctrcount),
	 getFloatFarenheitFromCount(ctrcount));
  printf("edgtmp = %d C  (%f F)\n",
	 getCentigradeFromCount(edgecount),
	 getFloatFarenheitFromCount(edgecount));
  return 0;
}
