#ifndef ITCPKTEVENT_H
#define ITCPKTEVENT_H

#include "linux/types.h"     /* for __u32 etc */
#include "pin_info_maps.h"

static inline __u32 mapDir6ToDir8(__u32 dir6) {
  switch (dir6) {
  default:      return DIR8_COUNT;
  case DIR6_ET: return DIR_NAME_TO_DIR8(ET);
  case DIR6_SE: return DIR_NAME_TO_DIR8(SE);
  case DIR6_SW: return DIR_NAME_TO_DIR8(SW);
  case DIR6_WT: return DIR_NAME_TO_DIR8(WT);
  case DIR6_NW: return DIR_NAME_TO_DIR8(NW);
  case DIR6_NE: return DIR_NAME_TO_DIR8(NE);
  }
}

static inline __u32 mapDir8ToDir6(__u32 dir8) {
  switch (dir8) {
  default:      return DIR6_COUNT;
  case DIR_NAME_TO_DIR8(ET): return DIR6_ET;
  case DIR_NAME_TO_DIR8(SE): return DIR6_SE;
  case DIR_NAME_TO_DIR8(SW): return DIR6_SW;
  case DIR_NAME_TO_DIR8(WT): return DIR6_WT;
  case DIR_NAME_TO_DIR8(NW): return DIR6_NW;
  case DIR_NAME_TO_DIR8(NE): return DIR6_NE;
  }
}

#define LEVELACTIONMACRO()                               \
  XX(DO_ILLEGAL,"illegal action")                        \
  XX(DO_REENTER,"go to stage 0 of current level")        \
  XX(DO_RESTART,"go to L00")                             \
  XX(DO_RETREAT,"go to stage 0 of previous level")       \
  XX(DO_ADVANCE,"go to next stage or level")             \
  XX(DO_CONTINUE,"stay at current level and stage")      \

typedef enum {

#define XX(a,b) a,
  LEVELACTIONMACRO()              
#undef XX
  LEVELACTION_COUNT
} LevelAction;

typedef __u8 LevelStage;                     /*  + level:3 + stage:2 */

inline static __u8 getLevelStageFromPacketByte(__u8 packetByte) { return packetByte&0x1f; /*bottom five bits*/ }
inline static __u8 getLevelFromLevelStage(LevelStage ls) { return (ls>>2)&0x7; }
inline static __u8 getStageFromLevelStage(LevelStage ls) { return (ls>>0)&0x3; }
inline static __u8 getLevelStageAsByte(LevelStage ls) { return (getLevelFromLevelStage(ls)<<4) | getStageFromLevelStage(ls); }

inline static __u8 makeLevelStage(__u32 level, __u32 stage) {
  return ((level&0x7)<<2)|((stage&0x3)<<0);
}



#define ITCPKTEVENT_TIME_SIZE 23
#define ITCPKTEVENT_EVENT_SIZE 9
typedef struct ITCPktEvent {
  __u32 time : ITCPKTEVENT_TIME_SIZE;
  __u32 event: ITCPKTEVENT_EVENT_SIZE; /*  xfr:2 + prio:1 + loglen:3 + dir:3 | spec:6 + 0:3 */
} ITCPktEvent;

enum {
  PEV_XFR_FROM_USR=0,
  PEV_XFR_TO_PRU=1,
  PEV_XFR_FROM_PRU=2,
  PEV_XFR_TO_USR=3,
};
#define PKTEVTSPECMACRO() \
  XX(QGAP,"event queue gap")  \
  XX(URTO,"user request timeout")  \
  XX(URDO,"user request done")  \
  XX(ACTO,"last active timeout")  \
  XX(WBKU,"blocking write from user")  \
  XX(RBKU,"blocking read from user")  \
  XX(WNBU,"non-blocking write from user")  \
  XX(RNBU,"non-blocking read from user")  \
  XX(WRTS,"write returns success")  \
  XX(WRTE,"write returns error")  \
  XX(RRTS,"read returns success")  \
  XX(RRTE,"read returns error")  \

enum {
#define XX(sym,str) PKTEVT_SPEC_##sym,
  PKTEVTSPECMACRO()
#undef XX  
  COUNT_PKTEVT_SPEC
};

static inline __u32 log2in3(__u32 nonzero) {
  __u32 leadingZeros = 32u - __builtin_clz(nonzero);
  return leadingZeros > 7u ? 7u : leadingZeros;
}

static inline __u32 makePktXfrEvent(__u32 xfr, __u32 prio, __u32 loglen, __u32 dir) {
  return ((xfr&0x3)<<7) | ((prio&0x1)<<6) | ((loglen&0x7)<<3) | ((dir&0x7)<<0);
}

static inline __u32 makeSpecPktEvent(__u8 code) {
  return ((code&0x3f)<<3) | ((0&0x7)<<0);
}

static inline __u32 getPktEvtDir(__u32 event) {
  return (event>>0)&0x7; 
}

static inline bool isXfrPktEvent(__u32 event) { return getPktEvtDir(event)!=0; }
static inline bool isSpecPktEvent(__u32 event) { return getPktEvtDir(event)==0; }

static inline bool unpackXfrPktEvent(__u32 event,__u32 * xfr,__u32 * prio,__u32 * loglen,__u32 * dir) {
  if (!isXfrPktEvent(event)) return false;
  if (xfr) *xfr = (event>>7)&0x3;
  if (prio) *prio = (event>>6)&0x1;
  if (loglen) *loglen = (event>>3)&0x7;
  if (dir) *dir = (event>>0)&0x7;
  return true;
}
static inline bool unpackSpecPktEvent(__u32 event,__u32 * code) {
  if (!isSpecPktEvent(event)) return false;
  if (code) *code = (event>>3)&0x3f;
  return true;
}

/**** KITC EVENTS ****/

enum {
  IEV_LST = 0,
  IEV_LSU = 1
};

#define IEVDIRMACRO() \
  XX(ITCDN,"packet sync lost") \
  XX(ITCUP,"packet sync acquired") \
  XX(UPBEG,"update begin") \
  XX(UPEND,"update end") \
  XX(RSRV4,"reserved") \
  XX(RSRV5,"reserved") \
  XX(RSRV6,"reserved") \
  XX(RSRV7,"reserved") \

enum {
#define XX(a,b) IEV_DIR_##a,
IEVDIRMACRO()
#undef XX
};

#define ITCEVTSPECMACRO() \
  LEVELACTIONMACRO()      \
  XX(QGAP,"event queue gap")  \
  XX(PTOU,"push timeout - us")   \
  XX(PTOT,"push timeout - them")   \
  XX(BITR,"begin iteration")   \
  XX(EITR,"end iteration")   \
  XX(LATE,"going again")   \
  XX(SLP0,"sleep <5ms")   \
  XX(SLP1,"sleep <50ms")   \
  XX(SLP2,"sleep <500ms")   \
  XX(SLP3,"sleep >=500ms")   \
  XX(INCOMPLETE_CODE,"XXX WHY DON'T YOU WRITE ME?")   \
    
enum {
#define XX(sym,str) IEV_SPEC_##sym,
  ITCEVTSPECMACRO()
#undef XX  
  COUNT_IEV_EVT_SPEC
};

static inline __u32 makeItcLSEvent(__u32 dir6, __u32 usNotThem, __u32 ls) {
  return ((dir6&0x7)<<6) | ((usNotThem&0x1)<<5) | ((ls&0x1f)<<0);
}

static inline __u32 makeItcDirEvent(__u32 dir6, __u32 op) {
  return ((6&0x7)<<6) | ((op&0x7)<<3) | ((dir6&0x7)<<0);
}

static inline __u32 makeItcSpecEvent(__u32 spec) {
  return ((7&0x7)<<6) | ((spec&0x3f)<<0);
}

static inline bool isItcLSEvent(__u32 event) { return (((event)>>6)&0x7) < 6; }

static inline bool isItcDirEvent(__u32 event) { return (((event)>>6)&0x7) == 6; }

static inline bool isItcSpecEvent(__u32 event) { return (((event)>>6)&0x7) == 7; }

static inline bool unpackItcLSEvent(__u32 event,__u32 * dir6,__u32 * usNotThem,__u32 * ls) {
  if (!isItcLSEvent(event)) return false;
  if (dir6) *dir6 = (event>>6)&0x7;
  if (usNotThem) *usNotThem = (event>>5)&0x1;
  if (ls) *ls = (event>>0)&0x1f;
  return true;
}

static inline bool unpackItcDirEvent(__u32 event,__u32 * dir6,__u32 * op) {
  if (!isItcDirEvent(event)) return false;
  if (dir6) *dir6 = (event>>0)&0x7;
  if (op) *op = (event>>3)&0x7;
  return true;
}

static inline bool unpackItcSpecEvent(__u32 event,__u32 * spec) {
  if (!isItcSpecEvent(event)) return false;
  if (spec) *spec = (event>>0)&0x3f;
  return true;
}


#endif /*ITCPKTEVENT_H*/
