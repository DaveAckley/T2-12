#ifndef ITCMFM_H                
#define ITCMFM_H

#include "linux/types.h"     /* for __u32 etc */
#include "linux/jiffies.h"   /* for HZ? */
#include "itc_iterator.h"

#include "itcpktevent.h"          /* Get pkt event struct */

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

static inline u32 msToJiffies(u32 ms) { return ms * HZ / 1000; }

typedef enum waitcode {
  WC_HALF,   
  WC_FULL,   
  WC_LONG,   
  WC_RANDOM, 
  MAX_WAIT_CODE
} WaitCode;

typedef enum waitms {
  WC_HALF_MS = 150,
  WC_FULL_MS = 300,
  WC_LONG_MS = 10000,
  WC_RANDOM_MIN_MS = 30,
  WC_RANDOM_MAX_MS = 1500,

  WC_RANDOM_WIDTH = WC_RANDOM_MAX_MS - WC_RANDOM_MIN_MS+1
} WaitMs;

static inline u32 jiffiesToWait(WaitCode wc) {
  switch (wc) {
  case WC_HALF:   return msToJiffies(WC_HALF_MS);
  case WC_FULL:   return msToJiffies(WC_FULL_MS);
  case WC_LONG:   return msToJiffies(WC_LONG_MS);
  case WC_RANDOM:
    return msToJiffies(prandom_u32_max(WC_RANDOM_WIDTH)+WC_RANDOM_MIN_MS);
  default: BUG_ON(1);
  }
}

typedef struct itcmfmdevicestate ITCMFMDeviceState;    /* FORWARD */

int kitcTimeoutThreadRunner(void *arg) ;
void wakeITCTimeoutRunner(void) ;

void handleKITCPacket(ITCMFMDeviceState * ds, u8 * packet, u32 len) ;

void resetKITC(ITCMFMDeviceState * mds) ;

#define MAX_MFZ_NAME_LENGTH 100
typedef u8 MFZId[MAX_MFZ_NAME_LENGTH + 1]; /* null-delimited 0..MAX_MFZ_NAME_LENGTH id string*/
typedef u8 MFMToken;                       /* random + incremented each id write, skipping 0 */
typedef u8 SeqNo;                          /* random + incremented each level packet, skipping 0 */

#define RANDOM_IN_SIZE(VAR_OR_TYPE)         \
  ({                                        \
    BUG_ON(sizeof(VAR_OR_TYPE) > 4);        \
    ((typeof(VAR_OR_TYPE)) prandom_u32());  \
  })

#define RANDOM_NONZERO_IN_SIZE(VAR_OR_TYPE)   \
  ({                                          \
    u32 __size = sizeof(VAR_OR_TYPE);         \
    u32 __lim = ( ((u64)1)<<(8*__size) )-1u;  \
    BUG_ON(__size > 4);                       \
    1u+prandom_u32_max(__lim);                \
  })

typedef struct {
  pid_t    mMFMPid;          /* pid that last wrote mToken */
  MFMToken mToken;    
  MFZId    mMFZId;  
} MFMTileState;

/* Functions & pointers */
typedef struct packethandler {
  u8 * pktbuf;
  u32 index;
  u32 len;
} PacketHandler;

typedef void StateTimeout_func (ITCMFMDeviceState* mds, PacketHandler * ph) ;
typedef void PacketReceive_func (ITCMFMDeviceState* mds, PacketHandler * ph) ;

typedef StateTimeout_func *StateTimeout_ptr;
typedef PacketReceive_func *PacketReceive_ptr;

typedef struct {
  StateTimeout_ptr  timeout;
  PacketReceive_ptr receive;
} ITCLSOps;

typedef struct {
  unsigned long mTimeout;       /* jiffies when we timeout */
  MFMToken   mToken;            /* Physics ID from MFM */
  MFZId      mMFZId;            /* MFZId from MFM */
  StateNumber mStateNumber;     /* Our state number */
  bool       mIsUs;             /* True if this is all about us */
} ITCSideState;


typedef struct {
  ITCSideState mUs;
  ITCSideState mThem;
} ITCLevelState;

#if 0
typedef struct {
  unsigned long mUTimeout;  /* Timeout for us, jiffies */
  unsigned long mTTimeout;  /* Timeout for them, jiffies */
  MFMToken   mTToken;       /* Last physics ID we got */
  LevelStage mTLastLS;      /* Last LevelStage from Them */
  MFZId      mTMFZId;       /* (Last) MFZId from Them */
  LevelStage mUCurrentLS;   /* Current LevelStage of Us */
  bool       mCompat;       /* True if Them and Us are known compatible */
} ITCLevelState;
#endif

void initITCLevelState(ITCLevelState * ils) ;
unsigned long itcLevelStateGetEarliestTimeout(ITCLevelState * ils);

extern ITCLSOps ilsDEFAULTS;

#endif /*ITCMFM_H*/
