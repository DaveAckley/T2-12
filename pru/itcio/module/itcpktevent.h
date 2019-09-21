#ifndef ITCPKTEVENT_H
#define ITCPKTEVENT_H

#include "linux/types.h"     /* for __u32 etc */

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

#endif /*ITCPKTEVENT_H*/
