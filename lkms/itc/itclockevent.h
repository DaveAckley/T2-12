#ifndef ITCLOCKEVENT_H
#define ITCLOCKEVENT_H

#include "linux/types.h"     /* for __u32 etc */
#include "dirdatamacro.h"    /* for STATE_COUNT */

#define ITCLOCKEVENT_TIME_SIZE 23
#define ITCLOCKEVENT_EVENT_SIZE 9
typedef struct itclockevent {
  __u32 time : ITCLOCKEVENT_TIME_SIZE;
  __u32 event: ITCLOCKEVENT_EVENT_SIZE; /* func:2 + arg:7 */
} ITCLockEvent;

enum {
  LET_FUNC_STATE=0,  /* state change: arg=dir:3+state:4*/                       
  LET_FUNC_PIN=1,    /* pin change: arg=dir:3+pin:2+value:1+unused:1 */
  LET_FUNC_USER=2,   /* user lockset: arg=lockset:6+current:1 */
  LET_FUNC_SPEC=3,   /* special event: arg=eventcode:7 */
};
#define LETSPECMACRO() \
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
  XX(RFIC,"refreshed inputs changed")  \
  XX(ALST,"all locks settled")  \

enum {
#define XX(sym,str) LET_SPEC_##sym,
  LETSPECMACRO()
#undef XX  
  COUNT_LET_SPEC
};

static inline __u32 makeStateLockEvent(__u32 dir, __u8 newstate) {
  return (LET_FUNC_STATE<<7) | ((dir&0x7)<<4) | ((newstate&0xf)<<0);
}

static inline __u32 makePinLockEvent(__u8 dir, __u8 pin, __u8 newvalue) {
  return (LET_FUNC_PIN<<7) | ((dir&0x7)<<4) | ((pin&0x3)<<2) | ((newvalue&0x1)<<1) | (0<<0);
}

static inline __u32 makeUserLockEvent(__u8 lockset) {
  return (LET_FUNC_USER<<7) | ((lockset&0x3f)<<1) | (0<<0);
}

static inline __u32 makeCurrentLockEvent(__u8 lockset) {
  return (LET_FUNC_USER<<7) | ((lockset&0x3f)<<1) | (1<<0);
}

static inline __u32 makeSpecLockEvent(__u8 code) {
  return (LET_FUNC_SPEC<<7) | ((code&0x7f)<<0);
}

static inline __u32 getLockEventFunc(__u32 event) {
  return (event>>7)&0x3; 
}

static inline bool isStateLockEvent(__u32 event) { return getLockEventFunc(event)==LET_FUNC_STATE; }
static inline bool isPinLockEvent(__u32 event)   { return getLockEventFunc(event)==LET_FUNC_PIN; }
static inline bool isUserLockEvent(__u32 event)  { return getLockEventFunc(event)==LET_FUNC_USER; }
static inline bool isSpecLockEvent(__u32 event)  { return getLockEventFunc(event)==LET_FUNC_SPEC; }

static inline bool unpackStateLockEvent(__u32 event,__u32 * dir,__u32 * state) {
  if (!isStateLockEvent(event)) return false;
  if (dir) *dir = (event>>4)&0x7;
  if (state) *state = (event>>0)&0xf;
  return true;
}
static inline bool unpackPinLockEvent(__u32 event,__u32 * dir,__u32 * pin,__u32 * val) {
  if (!isPinLockEvent(event)) return false;
  if (dir) *dir = (event>>4)&0x7;
  if (pin) *pin = (event>>2)&0x3;
  if (val) *val = (event>>1)&0x1;
  return true;
}
static inline bool unpackUserLockEvent(__u32 event,__u32 * lockset,__u32 * curflag) {
  if (!isUserLockEvent(event)) return false;
  if (lockset) *lockset = (event>>1)&0x3f;
  if (curflag) *curflag = (event>>0)&0x1;
  return true;
}
static inline bool unpackSpecLockEvent(__u32 event,__u32 * code) {
  if (!isSpecLockEvent(event)) return false;
  if (code) *code = (event>>0)&0x7f;
  return true;
}

#endif /*ITCLOCKEVENT_H*/
