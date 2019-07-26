#include <stdio.h>
#include <string.h>  /*for strcmp */
#include <sys/types.h>  /* for open */
#include <sys/stat.h>  /* for open */
#include <fcntl.h>  /* for open */
#include <unistd.h> /* for close */
#include <errno.h>  /* for errno */
#include <stdlib.h> /* for exit */
#include <stdint.h> /* for uint64_t */
#include <time.h>   /* for clock_gettime */

#include <stdbool.h> /* for bool, true, jeez */

#include "dirdatamacro.h" /*for DIR_ET etc, and sTAKEN etc*/

#define LOCK_DEV "/dev/itc/locks"
typedef unsigned char u8;

int openOrDie(void) {
  int fd = open(LOCK_DEV, O_RDWR/*|O_NONBLOCK*/);
  if (fd < 0) {
    fprintf(stderr, "Can't open %s: %s\n", LOCK_DEV, strerror(errno));
    exit(3);
  }
  return fd;
}
void closeOrDie(int fd) {
  int ret = close(fd);
  if (ret != 0) {
    fprintf(stderr, "Can't close %s: %s\n", LOCK_DEV, strerror(errno));
    exit(4);
  }
}

int writeCommand(int fd, u8 cmd) {
  return write(fd,&cmd,1);
}

unsigned readLocks(int fd, u8 *data, unsigned max) {
  int len = read(fd,data,max);
  if (len < 0) {
    fprintf(stderr, "Read failed: %s\n", strerror(errno));
    exit(5);
  } else if (len == 0) {
    fprintf(stderr, "Read 0\n");
  }
  return 1;
}
  
struct timespec diff(struct timespec start, struct timespec end)
{
  struct timespec temp;
  if ((end.tv_nsec-start.tv_nsec)<0) {
    temp.tv_sec = end.tv_sec-start.tv_sec-1;
    temp.tv_nsec = 1000000000+end.tv_nsec-start.tv_nsec;
  } else {
    temp.tv_sec = end.tv_sec-start.tv_sec;
    temp.tv_nsec = end.tv_nsec-start.tv_nsec;
  }
  return temp;
}
u8 eventSets[] = {
  (1<<DIR_ET)
  ,(1<<DIR_ET)|(1<<DIR_SE)
  ,(1<<DIR_SE)
  ,(1<<DIR_SE)|(1<<DIR_SW)
  ,(1<<DIR_SW)
  ,(1<<DIR_SW)|(1<<DIR_WT)
  ,(1<<DIR_WT)
  ,(1<<DIR_WT)|(1<<DIR_NW)
  ,(1<<DIR_NW)
  ,(1<<DIR_NW)|(1<<DIR_NE)
  ,(1<<DIR_NE)
  ,(1<<DIR_NE)|(1<<DIR_ET)
};
typedef enum { THREES, SIXGUNS, EVENTS } GenType;
int doEvents(int iterations) {
  int fd = openOrDie();
  int i;
  int ret;
  unsigned gotRequest = 0;
  unsigned failedRequest = 0;
  unsigned contestedRequest = 0;
  unsigned unreadyRequest = 0;
  unsigned timeoutRequest = 0;
  struct timespec start, stop;
  clock_gettime(CLOCK_MONOTONIC_RAW, &start);
  for (i = 0; i < iterations; ++i) {
    u8 byte = eventSets[random()%(sizeof(eventSets)/sizeof(eventSets[0]))];

    ret = writeCommand(fd,byte);
    if (ret > 0) ++gotRequest; 
    else switch (errno) {
    case ENXIO: ++unreadyRequest; break;
    case EBUSY: ++contestedRequest; break;
    case ETIME: ++timeoutRequest; break;
    default: 
      ++failedRequest; break;
    }
    ret = writeCommand(fd,'\0');
    if (ret < 0) {
      printf("Release all failed: %s\n",strerror(errno));
    }

  }
  clock_gettime(CLOCK_MONOTONIC_RAW, &stop);
  writeCommand(fd,0);
  closeOrDie(fd);
  {
    struct timespec elapsed = diff(start,stop);
    uint64_t nanos = ((uint64_t) elapsed.tv_sec)*1000u*1000u*1000u + elapsed.tv_nsec;
    double secs = nanos/(1000.0*1000*1000);
    printf("---\nTrials %d in %0.2f sec, %d usec/trial\n",
           i, secs, (int) (1.0*nanos/i/1000));
    printf("Succeeded: %d/%d%%\n",
           gotRequest, (int) (100.0*gotRequest/i+0.5));
    printf("Failures: contested: %d/%d%%, unready: %d/%d%%, timeout: %d/%d%%, other: %d/%d%% \n"
           ,contestedRequest, (int) (100.0*contestedRequest/i+.05)
           ,unreadyRequest, (int) (100.0*unreadyRequest/i+.05)
           ,timeoutRequest, (int) (100.0*timeoutRequest/i+.05)
           ,failedRequest, (int) (100.0*failedRequest/i+.05)
           );
  }

  return 0;
}


int speed1(int iterations,bool randomize,GenType type) {
  int fd = openOrDie();
  int i;
  unsigned maxSpins =  0;
  unsigned totalSpins = 0;
  unsigned gotRequest = 0;
  unsigned failedRequest = 0;
  struct timespec start, stop;
  clock_gettime(CLOCK_MONOTONIC_RAW, &start);
  for (i = 0; i < iterations; ++i) {
    u8 byte = randomize ? random()&0x7 : i&0x7;
    u8 readBuf[STATE_COUNT];
    if (i&8) byte <<= 3;
    switch (type) {
    case THREES:  break; /*default setup*/
    case SIXGUNS: byte = random()&0x3f; break;
    case EVENTS: 
      byte = eventSets[random()%(sizeof(eventSets)/sizeof(eventSets[0]))];
      break;
    default: exit(21);
    }

    writeCommand(fd,byte);
    {
      unsigned spins = readLocks(fd,readBuf,STATE_COUNT);
      if (spins > maxSpins) maxSpins = spins;
      totalSpins += spins;
      if (readBuf[sTAKEN] == byte) ++gotRequest;
      else {
        int k;
        ++failedRequest;
        for (k = 0; k <2; ++k) {
          printf("Trial %5d.%d spun %3d: Ask %02x, got %02x, %02x %02x %02x %02x %02x\n",
                 i,k,
                 spins,
                 byte,
                 readBuf[0],readBuf[1],
                 readBuf[2],readBuf[3],
                 readBuf[4],readBuf[5]);
          spins = readLocks(fd,readBuf,STATE_COUNT);
        }
      }
    }
  }
  clock_gettime(CLOCK_MONOTONIC_RAW, &stop);
  writeCommand(fd,0);
  closeOrDie(fd);
  {
    struct timespec elapsed = diff(start,stop);
    uint64_t nanos = ((uint64_t) elapsed.tv_sec)*1000u*1000u*1000u + elapsed.tv_nsec;
    double secs = nanos/(1000.0*1000*1000);
    printf("---\nTrials %d in %0.2f sec, %d usec/trial\n",
           i, secs, (int) (1.0*nanos/i/1000));
    printf("Succeeded: %d/%d%%, failed: %d/%d%% \n",
           gotRequest, (int) (100.0*gotRequest/i+0.5),
           failedRequest, (int) (100.0*failedRequest/i+.05));
    printf("Spins: %d max, %f avg\n",maxSpins, 1.0*totalSpins/i);
  }

  return 0;
}

int main(int argc, char **argv) {
  srandom(time(0));
  if (argc == 1) {
    printf("%s USETHESOURCE\n",argv[0]);
    return 1;
  }
  if (argc == 2 && !strcmp("speed1",argv[1])) return speed1(10000,false,THREES);
  if (argc == 2 && !strcmp("speed10",argv[1])) return speed1(10,false,THREES);
  if (argc == 2 && !strcmp("rand1",argv[1])) return speed1(10000,true,THREES);
  if (argc == 2 && !strcmp("rand10",argv[1])) return speed1(10,true,THREES);
  if (argc == 2 && !strcmp("sixgun1",argv[1])) return speed1(10000,true,SIXGUNS);
  if (argc == 2 && !strcmp("sixgun10",argv[1])) return speed1(10,true,SIXGUNS);
  if (argc == 2 && !strcmp("event1",argv[1])) return doEvents(10000);
  if (argc == 2 && !strcmp("event10",argv[1])) return doEvents(10);
  return 0;
}

