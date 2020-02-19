#ifndef ITCMFM_H                
#define ITCMFM_H

#include "linux/types.h"     /* for __u32 etc */
#include "itc_iterator.h"

typedef struct itcmfmdevicestate ITCMFMDeviceState;    /* FORWARD */

int itcLevelThreadRunner(void *arg) ;

void handleKITCPacket(ITCMFMDeviceState * ds, u8 * packet, u32 len) ;

void updateKITC(ITCMFMDeviceState * ds) ;

#define MAX_MFZ_NAME_LENGTH 100
typedef u8 MFZId[MAX_MFZ_NAME_LENGTH + 1]; /* null-delimited 0..MAX_MFZ_NAME_LENGTH id string*/
typedef u8 MFMToken;                       /* random + incremented each id write, skipping 0 */
typedef u8 LevelStage;                     /*  + level:3 + stage:2 */
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

inline static u8 getLevelStageFromPacketByte(u8 packetByte) { return packetByte&0x1f; /*bottom five bits*/ }
inline static u8 getLevelFromLevelStage(LevelStage ls) { return (ls>>2)&0x7; }
inline static u8 getStageFromLevelStage(LevelStage ls) { return (ls>>0)&0x3; }
inline static u8 getLevelStageAsByte(LevelStage ls) { return (getLevelFromLevelStage(ls)<<4) | getStageFromLevelStage(ls); }

inline static u8 makeLevelStage(u32 level, u32 stage) {
  return ((level&0x7)<<2)|((stage&0x3)<<0);
}

typedef struct {
  pid_t    mMFMPid;          /* pid that last wrote mToken */
  MFMToken mToken;    
  MFZId    mMFZId;  
} MFMTileState;

typedef enum {
  /* Zero means unset */
  DO_REENTER=1,
  DO_RESTART,
  DO_RETREAT,
  DO_ADVANCE,
  DO_CONTINUE,
  LEVELACTION_COUNT
} LevelAction;

/* Functions & pointers */
typedef bool        LevelRequire_func (ITCMFMDeviceState* mds);
typedef LevelAction LevelTimeout_func (ITCMFMDeviceState* mds,
                                       bool usNotThem,
                                       u32* ptrToNextTimeoutVarOrNull);
typedef u32         LevelPacketIO_func(ITCMFMDeviceState* mds,
                                       bool recvNotSend,
                                       u32 startIdx,
                                       u8* packetBuf,
                                       u32 buflen);
typedef LevelAction LevelDecide_func  (ITCMFMDeviceState* mds);
typedef bool        LevelAdvance_func (ITCMFMDeviceState* mds);

typedef LevelRequire_func *LevelRequire_ptr;
typedef LevelTimeout_func *LevelTimeout_ptr;
typedef LevelPacketIO_func *LevelPacketIO_ptr;
typedef LevelDecide_func *LevelDecide_ptr;
typedef LevelAdvance_func *LevelAdvance_ptr;

typedef struct {
  LevelRequire_ptr  require;
  LevelTimeout_ptr  timeout;
  LevelPacketIO_ptr packetio;
  LevelDecide_ptr   decide;
  LevelAdvance_ptr  advance;
} ITCLSOps;

typedef struct {
  unsigned long mLastAnnounce;  /* Time in jiffies (by local clock) */
  unsigned long mNextTimeout;   /* Based on timeout when last announce was set */
  LevelAction mTimeoutAction;   /* What to do it mNextTimeout hits */
  MFMToken   mToken;            /* Physics ID from MFM */
  MFZId      mMFZId;            /* MFZId from MFM */
  LevelStage mLevelStage;       /* This side's LevelStage */
  SeqNo      mSeqno;            /* Announcement sequence number */
  bool       mCompat;           /* True if Them and Us are known compatible */
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
