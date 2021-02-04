#ifndef ITCPKTEVENT_H
#define ITCPKTEVENT_H

#include "linux/types.h"     /* for __u32 etc */
#include "pin_info_maps.h"
#include "dirdatamacro.h"         /* For DIR6_ET, DIR6_COUNT, etc */

typedef enum packet_header_bits {
  PKT_HDR_BITMASK_STANDARD  = 0x80,
  PKT_HDR_BITMASK_LOCAL     = 0x40,
  PKT_HDR_BITMASK_MFM       = 0x20,

  PKT_HDR_BITMASK_STANDARD_LOCAL =
    PKT_HDR_BITMASK_STANDARD | PKT_HDR_BITMASK_LOCAL,

  PKT_HDR_BITMASK_STANDARD_MFM =
    PKT_HDR_BITMASK_STANDARD | PKT_HDR_BITMASK_MFM,

  // Standard Routed bits
  PKT_HDR_BITMASK_OVERRUN   = 0x10,
  PKT_HDR_BITMASK_ERROR     = 0x08,
  PKT_HDR_BITMASK_DIR       = 0x07,

  // Standard Local bits
  PKT_HDR_BITMASK_LOCAL_TYPE= 0x1f
} PacketHeaderBits;

typedef enum packet_header_byte1_bits {
  PKT_HDR_BYTE1_BITMASK_BULK = 0x80,      /* Bulk traffic (rather than flash) */
  PKT_HDR_BYTE1_BITMASK_XITC = 0xe0,      /* Types of ITC traffic */
  PKT_HDR_BYTE1_XITC_POS = __builtin_ctz(PKT_HDR_BYTE1_BITMASK_XITC),
  PKT_HDR_BYTE1_BITMASK_XITC_SN = 0x1f    /* State number bits */
} PacketHeaderByte1Bits;

typedef enum packet_header_byte1_xitc_values {
  PKT_HDR_BYTE1_XITC_VALUE_KITC =   0x0<<5, /* KITC (rather than userspace) */
  PKT_HDR_BYTE1_XITC_VALUE_ITCCMD = 0x1<<5, /* ITC command (userspace) */
  PKT_HDR_BYTE1_XITC_VALUE_CKT2 =   0x2<<5, /* Circuit ring (userspace) */
  PKT_HDR_BYTE1_XITC_VALUE_CKT3 =   0x3<<5, /* Call answered (userspace) */
  PKT_HDR_BYTE1_XITC_VALUE_CKT4 =   0x4<<5, /* Line busy (userspace) */
  PKT_HDR_BYTE1_XITC_VALUE_CKT5 =   0x5<<5, /* Call dropped (userspace) */
  PKT_HDR_BYTE1_XITC_VALUE_CKT6 =   0x6<<5, /* Talk (userspace) */
  PKT_HDR_BYTE1_XITC_VALUE_CKT7 =   0x7<<5  /* Call hangup (userspace) */
} PacketHeaderByte1XITCValues;

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
  XX(QGAP,"event queue gap")  \
  XX(PTOU,"push timeout - us")   \
  XX(PTOT,"push timeout - them")   \
  XX(BITR,"begin iteration")   \
  XX(RITR,"restart iteration")   \
  XX(EITR,"end iteration")   \
  XX(LATE,"going again")   \
  XX(SLP0,"sleep 0-4ms")   \
  XX(SLP1,"sleep 5-49ms")   \
  XX(SLP2,"sleep 50-499ms")   \
  XX(SLP3,"sleep 500+ms")   \
  XX(INCOMPLETE_CODE,"XXX WHY DON'T YOU WRITE ME?")   \
    
enum {
#define XX(sym,str) IEV_SPEC_##sym,
  ITCEVTSPECMACRO()
#undef XX  
  COUNT_IEV_EVT_SPEC
};

#define ITC_STATE_OPS_MACRO() \
  XX(ENTER)                   \
  XX(TIMEOUT)                 \
  XX(RECEIVE)                 \
  XX(SEND)                    \

typedef enum {
#define XX(sym) ITC_STATE_OP_##sym,
  ITC_STATE_OPS_MACRO()
#undef XX  
  COUNT_ITC_STATE_OPS
} ITCStateOp;

static inline __u32 makeItcStateEvent(__u32 dir6, __u32 stateNum, __u32 opNum) {
  return ((dir6&0x7)<<6) | ((opNum&0x3)<<4) | ((stateNum&0xf)<<0);
}

static inline __u32 makeItcStateEnterEvent(__u32 dir6, __u32 stateNum) {
  return makeItcStateEvent(dir6,stateNum,ITC_STATE_OP_ENTER);
}

static inline __u32 makeItcStateTimeoutEvent(__u32 dir6, __u32 stateNum) {
  return makeItcStateEvent(dir6,stateNum,ITC_STATE_OP_TIMEOUT);
}

static inline __u32 makeItcStateReceiveEvent(__u32 dir6, __u32 stateNum) {
  return makeItcStateEvent(dir6,stateNum,ITC_STATE_OP_RECEIVE);
}

static inline __u32 makeItcStateSendEvent(__u32 dir6, __u32 stateNum) {
  return makeItcStateEvent(dir6,stateNum,ITC_STATE_OP_SEND);
}

static inline __u32 makeItcDirEvent(__u32 dir6, __u32 op) {
  return ((6&0x7)<<6) | ((op&0x7)<<3) | ((dir6&0x7)<<0);
}

static inline __u32 makeItcSpecEvent(__u32 spec) {
  return ((7&0x7)<<6) | ((spec&0x3f)<<0);
}

static inline bool isItcStateEvent(__u32 event) { return (((event)>>6)&0x7) < 6; }

static inline bool isItcDirEvent(__u32 event) { return (((event)>>6)&0x7) == 6; }

static inline bool isItcSpecEvent(__u32 event) { return (((event)>>6)&0x7) == 7; }

static inline bool unpackItcStateEvent(__u32 event,__u32 * dir6,__u32 * state,__u32 * op) {
  if (!isItcStateEvent(event)) return false;
  if (dir6) *dir6 = (event>>6)&0x7;
  if (state) *state = (event>>0)&0xf;
  if (op) *op = (event>>4)&0x3;
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
