#include <stdio.h>
#include <unistd.h>  /* for read */
#include <string.h>  /*for strcmp */
#include <sys/types.h>  /* for open */
#include <sys/stat.h>  /* for open */
#include <fcntl.h>  /* for open */
#include <unistd.h> /* for close */
#include <errno.h>  /* for errno */
#include <stdlib.h> /* for exit */
#include <stdint.h> /* for uint64_t */
#include <time.h>   /* for clock_gettime */

#include "stdbool.h" /* for bool grr? */

#include "itclockevent.h"          /* Get lock event struct */
#include "RULES.h"

char *(dirnames[]) = {
#define XX(DC,fr,p1,p2,p3,p4) #DC,
  DIRDATAMACRO()
#undef XX
};

char *(statenames[]) = {
#define RSE(forState,output,settlement,...) RS(forState,forState,output,settlement,__VA_ARGS__)
#define RSN(forState,output,settlement,...) RS(forState,_,output,settlement,__VA_ARGS__)
#define RS(forstate,...) #forstate,
  ALLRULESMACRO()
#undef RS
#undef RSE
#undef RSN
};

#define LOCK_EVENT_DEV "/dev/itc/lockevents"

typedef unsigned char u8;

int openOrDie(void) {
  int fd = open(LOCK_EVENT_DEV, O_RDWR|O_NONBLOCK);
  if (fd < 0) {
    fprintf(stderr, "Can't open %s: %s\n", LOCK_EVENT_DEV, strerror(errno));
    exit(3);
  }
  return fd;
}
void closeOrDie(int fd) {
  int ret = close(fd);
  if (ret != 0) {
    fprintf(stderr, "Can't close %s: %s\n", LOCK_EVENT_DEV, strerror(errno));
    exit(4);
  }
}

void writeCommand(int fd, u8 cmd) {
  int len = write(fd,&cmd,1);
  if (len < 0) {
    fprintf(stderr, "Write failed: %s\n", strerror(errno));
    exit(5);
  } else if (len == 0) {
    fprintf(stderr, "Wrote 0\n");
  }
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

static int readWholeFile(const char* path, char * buffer, unsigned len) {
  FILE * fd = fopen(path, "r");
  int i;
  if (!fd) {
    fprintf(stderr, "Can't open %s: %s\n", path, strerror(errno));
    return -1;
  }
  for (i = 0; i < len; ++i) {
    int ch = fgetc(fd);
    if (ch < 0) break;
    buffer[i] = (char) ch;
  }
  if (fclose(fd) < 0) {
    fprintf(stderr, "Can't close %s: %s\n", path, strerror(errno));
    return -2;
  }
  if (i >= len)
    return -3;

  buffer[i] = '\0';
  return i;
}

static int readOneLinerFile(const char* path, char * buffer, unsigned len) {
  int read = readWholeFile(path,buffer,len);
  if (read < 0) return read;
  if (read > 0 && buffer[read-1] == '\n') buffer[--read] = '\0';
  return read;
}

static int readOneDecimalNumber(const char* path,  __s64 * valret) {
  char buf[100];
  int read = readOneLinerFile(path,buf,100);
  __s64 tmp;
  if (read < 0) return read;
  if (sscanf(buf,"%lld", &tmp) <= 0) return -1;
  *valret = tmp;
  return 0;
}

static __u64 getStartTime(void)  {
  __s64 time;
  if (readOneDecimalNumber("/sys/class/itc/trace_start_time",&time))
    exit(7);
  return (__u64) time;
}

static unsigned getShift(void)  {
  __s64 num;
  if (readOneDecimalNumber("/sys/class/itc/shift",&num))
    exit(7);
  return (unsigned) num;
}
const char * getDirName(__u32 dir) {
  if (dir < sizeof(dirnames)/sizeof(dirnames[0]))
    return dirnames[dir];
  return "XX";
 }
const char * getPinName(__u32 pin) {
  switch(pin) {
  case PIN_IRQLK: return "IRQLK";
  case PIN_IGRLK: return "IGRLK";
  case PIN_ORQLK: return "ORQLK";
  case PIN_OGRLK: return "OGRLK";
  default: return "????";
  }
}
bool isInput(__u32 pin) {
  return pin == PIN_IRQLK || pin == PIN_IGRLK;
}
const char *(specsymnames[]) = {
#define XX(sym,str) #sym,
  LETSPECMACRO()
#undef XX
  0
};

const char *(specsymdesc[]) = {
#define XX(sym,str) str,
  LETSPECMACRO()
#undef XX
  0
};

const char * getSpecSymName(__u32 spec) {
  if (spec < sizeof(specsymnames)/sizeof(specsymnames[0]))
    return specsymnames[spec];
  return "specsymname?";
 }

const char * getSpecSymDesc(__u32 spec) {
  if (spec < sizeof(specsymdesc)/sizeof(specsymdesc[0]))
    return specsymdesc[spec];
  return "specsymdesc?";
 }

int dumpevents(void) {
  int fd = openOrDie();
  int shift = getShift();
  __u64 start = getStartTime();
  __u64 first = 0;
  __u64 last = 0;
  ITCLockEvent tmp;
  int eventsDumped = 0;
  printf("Start time %lld\n",start);
  while (read(fd,(void*) &tmp, 4) == 4) {
    __u64 nanos = (((__u64)tmp.time)<<shift);
    double sec;
    __u32 incrns;
    char * incrunit="usec";
    char eventbuf[100];
    __u32 event = tmp.event;
    if (isStateLockEvent(event)) {
      __u32 dir, state;
      const char * dirname;
      const char * statename;
      unpackStateLockEvent(event,&dir,&state);
      dirname = getDirName(dir);
      
      if (state < sizeof(statenames)/sizeof(statenames[0]))
        statename = statenames[state];
      else
        statename = "??";
      snprintf(eventbuf,100,"     [%s %s]",dirname,statename);
    } else if (isPinLockEvent(event)) {
      __u32 dir, pin, val;
      const char * dirname;
      const char * pinname;
      
      unpackPinLockEvent(event,&dir,&pin,&val);
      dirname = getDirName(dir);
      pinname = getPinName(pin);
      if (isInput(pin)) {
        snprintf(eventbuf,100," %s%s_%s",val?"+":"-",dirname,pinname);
      } else {
        snprintf(eventbuf,100,"         %s_%s%s",dirname,pinname,val?"+":"-");
      }
    } else if (isUserLockEvent(event)) {
      __u32 lockset, current;
      int pos = 0;
      int i;
      unpackUserLockEvent(event,&lockset, &current);
      pos += snprintf(&eventbuf[pos],100-pos,"%s lockset=%02x",
                      current ? "Curr" : "User",lockset);
      for (i = 0; i < 6; ++i) {
        pos += snprintf(&eventbuf[pos],100-pos," %s",
                        (lockset & (1<<i)) ? getDirName(i) : "__");
      }
    } else if (isSpecLockEvent(event)) {
      __u32 code;
      unpackSpecLockEvent(event,&code);
      snprintf(eventbuf,100,"%s: %s",
               getSpecSymName(code),
               getSpecSymDesc(code)
               );
    } else {
      exit(12);
    }

    if (first == 0) first = nanos;
    sec = (nanos-first)/(1000.0*1000.0*1000.0);
    if (last == 0) last = nanos;
    incrns = (__u32) (nanos-last);
    last = nanos;
    if (incrns > 1000*1000) {
      incrns /= 1000;
      incrunit = "msec";
    }
    printf("%04d %8.6fsec %+4d%s %03x:%s\n",
           ++eventsDumped, sec, incrns/1000, incrunit, tmp.event, eventbuf);
  }
  closeOrDie(fd);
  return 0;
}

int main(int argc, char **argv) {
  if (argc == 1) {
    printf("%s USETHESOURCE\n",argv[0]);
    return 1;
  }
  if (argc == 2 && !strcmp("dumpevents",argv[1])) return dumpevents();
  return 0;
}
