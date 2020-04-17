#include "tnv.h"
#include "T2ADCs.h"
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

static void print0(int count, bool machine) {
  printf(machine ? "%f" : "Vgrid = %f V", gridVoltage(count));
}
static void print1(int count, bool machine) {
  if (machine) printf("%f", getFloatFarenheitFromCount(count));
  else
    printf("ctrtmp = %d C  (%f F)",
           getCentigradeFromCount(count),
           getFloatFarenheitFromCount(count));
}
static void print2(int count, bool machine) {
  if (machine) printf("%f", getFloatFarenheitFromCount(count));
  else
    printf("edgtmp = %d C  (%f F)",
           getCentigradeFromCount(count),
           getFloatFarenheitFromCount(count));
}
static void print3(int count, bool machine) {
  if (machine) printf("%d", count);
}
static void print4(int count, bool machine) {
  if (machine) printf("%d", count);
}
static void print5(int count, bool machine) {
  bool lo = count < 2000;
  if (machine) printf("%d", lo);
  else
    printf("BUTTON %s",lo ? "DOWN" : "UP");
}
static void print6(int count, bool machine) {
  if (machine) printf("%d", count);
}

static struct channelHandler {
  unsigned channelnum;
  const char * adcname;
  void (*printer)(int,bool);
  int takeReading() {
    int val = readChannel(channelnum);
    return val;
  }
} adcHandlers[] = {
  { 0, "GRDVLT_A", print0 },
  { 1, "CTRTMP_A", print1 },
  { 2, "EDGTMP_A", print2 },
  { 3, "ADCRSRV2", print3 },
  { 4, "ADCRSRV1", print4 },
  { 5, "USER_ACT", print5 },
  { 6, "ADCLIGHT", print6 },
};

int main(int argc, char **argv) {
  bool machine = argc > 1;
  MFM::T2ADCs adcs;
  adcs.update();
  for (unsigned i = 0; i < 7; ++i) {
    MFM::T2ADCs::ADCChannel chnl = (MFM::T2ADCs::ADCChannel) i;
    struct channelHandler & ch = adcHandlers[i];
    int raw = adcs.getChannelRawData(chnl);
    if (!machine) {
      printf("%d %s = %4d raw ", i, ch.adcname, raw);
    }
    if (ch.printer) {
      ch.printer(raw,machine);
    }
    printf(machine && i < 6 ? " " : "\n");
  }
  return 0;
}
