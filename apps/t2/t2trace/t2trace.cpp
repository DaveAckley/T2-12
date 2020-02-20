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
#include "itcpktevent.h"          /* Get pkt event struct */
#include "RULES.h"

namespace Dirs {
  typedef unsigned char Dir;
    static const Dir NORTH     = 0;
    static const Dir NORTHEAST = 1;
    static const Dir EAST      = 2;
    static const Dir SOUTHEAST = 3;
    static const Dir SOUTH     = 4;
    static const Dir SOUTHWEST = 5;
    static const Dir WEST      = 6;
    static const Dir NORTHWEST = 7;
    static const Dir DIR_COUNT = 8;
}

#if 0  /*supplied by itcpkt.h*/
static inline __u32 mapDir8ToDir6(__u32 dir8) {
  switch (dir8) {
  case Dirs::NORTH: 
  case Dirs::SOUTH: 
  default: return DIR_COUNT;
      
  case Dirs::NORTHEAST: return DIR_NE;
  case Dirs::EAST:      return DIR_ET;
  case Dirs::SOUTHEAST: return DIR_SE;
  case Dirs::SOUTHWEST: return DIR_SW;
  case Dirs::WEST:      return DIR_WT;
  case Dirs::NORTHWEST: return DIR_NW;
  }
}
#endif

const char *dirnames[] = {
#define XX(DC,fr,p1,p2,p3,p4) #DC,
  DIRDATAMACRO()
#undef XX
};

const char *statenames[] = {
#define RSE(forState,output,settlement,...) RS(forState,forState,output,settlement,__VA_ARGS__)
#define RSN(forState,output,settlement,...) RS(forState,_,output,settlement,__VA_ARGS__)
#define RS(forstate,...) #forstate,
  ALLRULESMACRO()
#undef RS
#undef RSE
#undef RSN
};

#define LOCK_EVENT_DEV "/dev/itc/lockevents"
#define LOCK_TIME_PATH "/sys/class/itc/trace_start_time"
#define LOCK_SHIFT_PATH "/sys/class/itc/shift"

#define PKT_EVENT_DEV "/dev/itc/pktevents"
#define PKT_TIME_PATH "/sys/class/itc_pkt/trace_start_time"
#define PKT_SHIFT_PATH "/sys/class/itc_pkt/shift"

const char * getXfrName(__u32 xfr) {
  switch (xfr) {
  case PEV_XFR_FROM_USR: return "from USR";
  case PEV_XFR_TO_PRU:   return "to PRU";
  case PEV_XFR_FROM_PRU: return "from PRU";
  case PEV_XFR_TO_USR:   return "to USR";
  default: return "??";
  }
}

const char * getDir6Name(__u32 dir) {
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

//// LOCK SPECIALS
const char *specsymnames[] = {
#define XX(sym,str) #sym,
  LETSPECMACRO()
#undef XX
  0
};

const char *specsymdesc[] = {
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

//// PKT SPECIALS
const char *pktspecsymnames[] = {
#define XX(sym,str) #sym,
  PKTEVTSPECMACRO()
#undef XX
  0
};

const char *pktspecsymdesc[] = {
#define XX(sym,str) str,
  PKTEVTSPECMACRO()
#undef XX
  0
};

const char * getPktSpecSymName(__u32 spec) {
  if (spec < sizeof(pktspecsymnames)/sizeof(pktspecsymnames[0]))
    return pktspecsymnames[spec];
  return "pktspecsymname?";
 }

const char * getPktSpecSymDesc(__u32 spec) {
  if (spec < sizeof(pktspecsymdesc)/sizeof(pktspecsymdesc[0]))
    return pktspecsymdesc[spec];
  return "pktspecsymdesc?";
}

typedef unsigned char u8;

int openOrDie(const char * name) {
  int fd = open(name, O_RDWR|O_NONBLOCK);
  if (fd < 0) {
    fprintf(stderr, "Can't open %s: %s\n", name, strerror(errno));
    exit(3);
  }
  return fd;
}
int openOrDieLOCK(void) { return openOrDie(LOCK_EVENT_DEV); }
int openOrDiePKT(void) { return openOrDie(PKT_EVENT_DEV); }

void closeOrDie(int fd, const char * name)
{
  int ret = close(fd);
  if (ret != 0) {
    fprintf(stderr, "Can't close %s: %s\n", name, strerror(errno));
    exit(4);
  }
}
void closeOrDieLOCK(int fd) { closeOrDie(fd, LOCK_EVENT_DEV); }
void closeOrDiePKT(int fd) { closeOrDie(fd, PKT_EVENT_DEV); }

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
  unsigned i;
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

struct EventSource {
  EventSource(const char * sourceName, const char * evtPath,const char * timePath,const char * shiftPath)
    : mSourceName(sourceName)
    , mEventPath(evtPath)
    , mStartTimePath(timePath)
    , mShiftPath(shiftPath)
    , mHaveLast(false)
    , mFd(-1)
    , mShift(-1)
    , mStart(0)
  {
    init();
  }

  virtual void unpackEvent(char buffer[100]) = 0;

  virtual bool atStoppingEvent() = 0;

  virtual ~EventSource() { deinit(); }

  virtual __u32 getTimeField() const = 0;
  virtual __u32 getEventField() const = 0;
  virtual bool readNext() = 0;

  void openEvt() {
    if (mFd >= 0) abort();
    int fd = open(mEventPath, O_RDWR|O_NONBLOCK);
    if (fd < 0) {
      fprintf(stderr, "Can't open %s: %s\n", mEventPath, strerror(errno));
      exit(3);
    }
    mFd = fd;
  }
  void closeEvt() {
    if (mFd < 0) abort();
    int ret = close(mFd);
    if (ret != 0) {
      fprintf(stderr, "Can't close %s: %s\n", mEventPath, strerror(errno));
      exit(4);
    }
    mFd = -1;
  }
  void load() {
    __s64 tmp;
    if (readOneDecimalNumber(mStartTimePath,&tmp))
      exit(7);
    mStart = tmp;
    if (readOneDecimalNumber(mShiftPath,&tmp))
      exit(7);
    mShift = (int) tmp;
  }

  void init() {
    load();
    openEvt();
    printf("%s: shift=%d, start=%llu\n",
           mSourceName,
           mShift,
           mStart);
  }

  void deinit() {
    closeEvt();
  }
  
  __u64 getStartTime() const {
    return mStart;
  }

  bool getEventTime(__u64 & when) {
    if (!mHaveLast && !tryRead()) return false;
    if (!mHaveLast) return false;
    when = (getTimeField()<<mShift) + mStart;
    return true;
  }

  __u32 getEventValue() {
    if (!mHaveLast && !tryRead()) return 0;
    if (!mHaveLast) return 0;
    return getEventField();
  }

  bool tryRead() {
    mHaveLast = false;
    if (!readNext()) return false;
    return mHaveLast = true;
  }

  const char * mSourceName;
  const char * mEventPath;
  const char * mStartTimePath;
  const char * mShiftPath;
  bool mHaveLast;
  int mFd;
  int mShift;
  __u64 mStart;
};

struct EventSourceLock : public EventSource {
  EventSourceLock()
    : EventSource("Locks", LOCK_EVENT_DEV,LOCK_TIME_PATH,LOCK_SHIFT_PATH)
    , mPrevCode(-1)
  { }

  __s32 mPrevCode;
  ITCLockEvent mLast;
  __u32 getTimeField() const { return mLast.time; }
  __u32 getEventField() const { return mLast.event; }

  virtual bool atStoppingEvent() {
    if (!mHaveLast || !isSpecLockEvent(getEventField())) return false;
    __u32 code;
    unpackSpecLockEvent(getEventField(),&code);
    return code == LET_SPEC_QGAP;
  }

  virtual void unpackEvent(char eventbuf[100]) {
    __u32 event = getEventField();
    if (isStateLockEvent(event)) {
      __u32 dir, state;
      const char * dirname;
      const char * statename;
      unpackStateLockEvent(event,&dir,&state);
      dirname = getDir6Name(dir);
      
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
      dirname = getDir6Name(dir);
      pinname = getPinName(pin);
      if (isInput(pin)) {
        snprintf(eventbuf,100," %s%s_%s",val?"+":"-",dirname,pinname);
      } else {
        snprintf(eventbuf,100,"         %s_%s%s",dirname,pinname,val?"+":"-");
      }
    } else if (isUserLockEvent(event)) {
      const char * statename = 0;
      __u32 lockset, current;
      int pos = 0;
      int i;
      unpackUserLockEvent(event,&lockset, &current);
      if (!current)
        pos += snprintf(&eventbuf[pos],100-pos,"%s lockset=%02x",
                        "User",lockset);
      else {
        if (mPrevCode < 0)  // curr lockset without prev spec lock event?
          pos += snprintf(&eventbuf[pos],100-pos,"%s lockset=%02x",
                          "????",lockset);
        else {
          pos += snprintf(&eventbuf[pos],100-pos,"Curr lockset=%02x", lockset);
          statename = statenames[mPrevCode-LET_SPEC_CLS0];
        }
      }
      for (i = 0; i < 6; ++i) {
        pos += snprintf(&eventbuf[pos],100-pos," %s",
                        (lockset & (1<<i)) ? getDir6Name(i) : "__");
      }
      if (statename)
        pos += snprintf(&eventbuf[pos],100-pos," are %s", statename);

    } else if (isSpecLockEvent(event)) {
      __u32 code;
      unpackSpecLockEvent(event,&code);
      if (code < LET_SPEC_CLS0 || code > LET_SPEC_CLSF) // Don't report modifiers for next event
        snprintf(eventbuf,100,"L%s: %s",
                 getSpecSymName(code),
                 getSpecSymDesc(code)
                 );
    } else {
      exit(12);
    }
  }

  bool readMLast() {
    unsigned got = read(mFd,&mLast,sizeof(mLast));
    if (got == 0) return false;
    if (got != sizeof(mLast)) abort();
    return true;
  }

  bool readNext() {
    if (!readMLast()) return false;
    mPrevCode = codeOfSpecLockEvent(mLast.event);
    if (mPrevCode >= LET_SPEC_CLS0 && mPrevCode <= LET_SPEC_CLSF)
      return readMLast(); // Skip prefix codes
    else mPrevCode = -1; // No current prefix
    return true;
  }

};

struct EventSourcePkt : public EventSource {
  EventSourcePkt() : EventSource("Packets", PKT_EVENT_DEV,PKT_TIME_PATH,PKT_SHIFT_PATH) { }
  ITCPktEvent mLast;
  __u32 getTimeField() const { return mLast.time; }
  __u32 getEventField() const { return mLast.event; }

  virtual bool atStoppingEvent() {
    if (!mHaveLast || !isSpecPktEvent(getEventField())) return false;
    __u32 code;
    unpackSpecPktEvent(getEventField(),&code);
    return code == PKTEVT_SPEC_QGAP;
  }

  virtual void unpackEvent(char eventbuf[100]) {
    __u32 event = getEventField();
    if (isXfrPktEvent(event)) {
      __u32 xfr, prio, loglen, minlen, maxlen, dir8;
      const char * xfrname;
      const char * dirname;
      if (!unpackXfrPktEvent(event,&xfr,&prio,&loglen,&dir8)) abort();
      minlen = 1<<(loglen-1);
      maxlen = 1<<loglen;
      xfrname = getXfrName(xfr);
      dirname = getDir6Name(mapDir8ToDir6(dir8));
      const char * spacer = "";
      if (xfr == PEV_XFR_TO_PRU) spacer = "  ";
      else if (xfr == PEV_XFR_FROM_PRU) spacer = "    ";
      else if (xfr == PEV_XFR_TO_USR) spacer = "      ";
      
      snprintf(eventbuf,100,"%s<%s %s %d-%d>",spacer,dirname,xfrname,minlen,maxlen);
      
    } else if (isSpecPktEvent(event)) {
      __u32 code;
      if (!unpackSpecPktEvent(event,&code)) abort();
      const char * specname = getPktSpecSymName(code);
      const char * specdesc = getPktSpecSymDesc(code);
 
      snprintf(eventbuf,100,"P%s: %s", specname, specdesc);
    } else abort();
  }
  bool readNext() {
    unsigned got = read(mFd,&mLast,sizeof(mLast));
    if (got == 0) return false;
    if (got != sizeof(mLast)) abort();
    return true;
  }
};

struct Reporter {
  Reporter(__u64 startNanos)
    : mEventsDumped(0)
    , mFirst(0)
    , mLast(0)
    , mCurNanos(startNanos)
  { }
  
  int mEventsDumped;
  __u64 mFirst;
  __u64 mLast;
  __u64 mCurNanos;

  __u32 formatDelta(__u64 deltaNanos, bool negsign, char * buf, __u32 len) {
    const char * unit;
    if (deltaNanos == 0) return snprintf(buf,len,"  +0usec");
    do {
      if (deltaNanos < 1000) { unit = "nsec"; break; }
      deltaNanos /= 1000;
      if (deltaNanos < 1000) { unit = "usec"; break; }
      deltaNanos /= 1000;
      if (deltaNanos < 1000) { unit = "msec"; break; }
      deltaNanos /= 1000;
      if (deltaNanos < 1000) { unit = "secs"; break; }
      deltaNanos /= 60;
      if (deltaNanos < 1000) { unit = "mins"; break; }
      deltaNanos /= 60;
      if (deltaNanos < 1000) { unit = "hour"; break; }
      deltaNanos /= 24;
      if (deltaNanos < 1000) { unit = "days"; break; }
      deltaNanos /= 365;
      if (deltaNanos < 1000) { unit = "year"; break; }
      // Screw you
      unit = "lies";
    } while (0);
    if (negsign)
      return snprintf(buf,len,"%+4d%s",-(__s32) deltaNanos, unit);
    return snprintf(buf,len,"%+4d%s",(__u32) deltaNanos, unit);
  }

  void reportEvent(EventSource & es, bool dump) {
    __u64 nanos;
    if (!es.getEventTime(nanos)) abort();

    double sec;
    __u64 incrns;

    if (dump) {
      char eventbuf[100];
      char delta1[20];
      bool negsec = false, negincr = false;
      //      char delta2[20];
      es.unpackEvent(eventbuf);

      if (mFirst == 0) mFirst = nanos;
      if (nanos >= mFirst)
        sec = (nanos-mFirst)/(1000.0*1000.0*1000.0);
      else {
        negsec = true;
        sec = (mFirst-nanos)/(1000.0*1000.0*1000.0);
      }
      if (mLast == 0) mLast = nanos;
      if (nanos >= mLast) {
        incrns = (nanos-mLast);
      } else {
        negincr = true;
        incrns = (mLast-nanos);
      }
      mLast = nanos;
      formatDelta(incrns, negincr, delta1, 20);

      printf("%04d %s%8.6fsec%s%s %03x:%s\n",
             ++mEventsDumped,
             negsec ? "-" : " ", sec,
             negincr ? " " : " ", delta1,
             es.getEventValue(), eventbuf);

      mCurNanos = nanos;
    }

    es.tryRead();
  }
};

int dumpevents(bool dumplocks, bool dumppackets) {
  EventSourceLock lev;
  EventSourcePkt pev;
  __u64 start = 0;
  if (dumplocks && lev.getStartTime() > start) start = lev.getStartTime();
  if (dumppackets && pev.getStartTime() > start) start = pev.getStartTime();

  Reporter rep(start);

  int eventsDumped = 0;
  printf("Start time %lld\n",start);
  bool haveLev, havePev;
  __u64 curLev, curPev;

  while (!lev.atStoppingEvent() && ! pev.atStoppingEvent()) {
    haveLev = lev.getEventTime(curLev);
    havePev = pev.getEventTime(curPev);
    if (!haveLev && !havePev) break;
    // Discard events prior to later start
    if (curLev < start && dumplocks) { lev.tryRead(); continue; } 
    if (curPev < start && dumppackets) { pev.tryRead(); continue; }
    ++eventsDumped;
    if (haveLev && havePev) {
      if (curLev < curPev) rep.reportEvent(lev,dumplocks);
      else rep.reportEvent(pev,dumppackets);
    } else if (haveLev) rep.reportEvent(lev,dumplocks);
    else rep.reportEvent(pev,dumppackets);
  }
  return 0;
}

int main(int argc, char **argv) {
  if (argc == 1) {
    printf("%s USETHESOURCE\n",argv[0]);
    return 1;
  }
  if (argc == 2 && !strcmp("dumpevents",argv[1])) return dumpevents(true,true);
  if (argc == 2 && !strcmp("dumplocks",argv[1])) return dumpevents(true,false);
  if (argc == 2 && !strcmp("dumppackets",argv[1])) return dumpevents(false,true);
  return 2;
}
