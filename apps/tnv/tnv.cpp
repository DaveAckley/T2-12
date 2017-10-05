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

unsigned conditionOlive(unsigned raw, int argc, char **argv) {
  unsigned adder = 115;
  unsigned shifter = 6;
  if (argc > 1) {
    adder = atoi(argv[1]);
    if (argc > 2)
      shifter = atoi(argv[2]);
  }
  return ~((raw+adder)>>shifter)&0x3f;
}

unsigned readOlive() {
  unsigned bits = 8;
  unsigned samples = 1<<bits;
  unsigned sum = 0;
  for (unsigned i = 0; i < samples; ++i)
    sum += readChannel(3);
  return sum/samples;
}

static const char * dirs[] = {"SE", "NW", "WT", "ET", "SW", "NE" };
void printOlive(unsigned raw, unsigned cooked)
{
  printf("olive = 0x%02x (0x%03x raw)", cooked, raw);
  for (unsigned i = 0; i < 6; ++i) {
    if (cooked&(1<<i)) printf(" %s",dirs[i]);
    else               printf(" --");
  }
  printf("\n");
}


int main(int argc, char **argv) {
  unsigned rawolive = readOlive();
  unsigned olivecount = conditionOlive(rawolive,argc,argv);
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
  printOlive(rawolive,olivecount);
  return 0;
}
