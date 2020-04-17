#ifndef ITCMFM_H                
#define ITCMFM_H

#include "linux/types.h"     /* for __u32 etc */
#include "linux/jiffies.h"   /* for HZ? */
#include "itc_iterator.h"

#include "itcpktevent.h"          /* Get pkt event struct */
#include "itcmfmevent.h"          /* Get state macro defs */

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

  WC_LONG_MIN_MS = 10000,
  WC_LONG_MAX_MS = 15000,
  WC_LONG_WIDTH = WC_LONG_MAX_MS - WC_LONG_MIN_MS+1,

  WC_RANDOM_MIN_MS = 30,
  WC_RANDOM_MAX_MS = 1500,

  WC_RANDOM_WIDTH = WC_RANDOM_MAX_MS - WC_RANDOM_MIN_MS+1
} WaitMs;

static inline u32 jiffiesToWait(WaitCode wc) {
  switch (wc) {
  case WC_HALF:   return msToJiffies(WC_HALF_MS);
  case WC_FULL:   return msToJiffies(WC_FULL_MS);
  case WC_LONG:   return msToJiffies(prandom_u32_max(WC_LONG_WIDTH)+WC_LONG_MIN_MS);
  case WC_RANDOM: return msToJiffies(prandom_u32_max(WC_RANDOM_WIDTH)+WC_RANDOM_MIN_MS);
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
  MFZId    mMFZId;           /* our MFZId as written to /sys/class/itc_pkt/mfzid */
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
} ITCSOps;

typedef struct {
  unsigned long mTimeout;       /* jiffies when we timeout */
  MFMToken   mToken;            /* Physics ID from MFM */
  MFZId      mMFZIdThem;        /* MFZId from their MFM (ours is in S.mMFMTileState) */
  StateNumber mStateNumber;     /* Our state number */
} ITCState;

void initITCState(ITCState * is) ;
unsigned long itcStateGetEarliestTimeout(ITCState * is) ;
bool isKITCCompatible(ITCMFMDeviceState * mds) ;

extern ITCSOps ilsDEFAULTS;

#endif /*ITCMFM_H*/
