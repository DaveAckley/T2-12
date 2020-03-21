#ifndef ITCMFMEVENT_H
#define ITCMFMEVENT_H

/**** EARLY STATES HACKERY ****/

#define ALL_STATES_MACRO()                                    \
/*   name         custo cusrc desc) */                        \
  XX(INIT,        0,    0,    "initialized state")            \
  XX(WAITPS,      1,    0,    "wait for packet sync")         \
  XX(LEAD,        1,    1,    "declare I am leader")          \
  XX(WLEAD,       0,    0,    "wait for follower ack")        \
  XX(FOLLOW,      1,    1,    "declare I am follower")        \
  XX(WFOLLOW,     0,    0,    "wait for config")              \
  XX(CONFIG,      1,    1,    "send leader config")           \
  XX(WCONFIG,     0,    0,    "wait for follower config")     \
  XX(CHECK,       1,    1,    "send follower config")         \
  XX(COMPATIBLE,  1,    1,    "pass MFM traffic")             \
  XX(INCOMPATIBLE,1,    1,    "block MFM traffic")            \

/*** STATE NUMBERS **/
typedef enum statenumber {
#define XX(NAME,CUSTO,CUSRC,DESC) SN_##NAME,
  ALL_STATES_MACRO()
#undef XX
  MAX_STATE_NUMBER
} StateNumber;

/*** STATE NUMBER BITMASKS **/
#define MASK_OF(sn) (1<<sn);

typedef enum statenumbermask {
#define XX(NAME,CUSTO,CUSRC,DESC) SN_##NAME##_MASK = 1<<SN_##NAME,
  ALL_STATES_MACRO()
#undef XX
  MASK_ALL_STATES = -1
} StateNumberMask;

#endif /*ITCMFMEVENT_H*/
