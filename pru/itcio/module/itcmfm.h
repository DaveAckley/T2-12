#ifndef ITCMFM_H                
#define ITCMFM_H

#include "linux/types.h"     /* for __u32 etc */

typedef struct itcmfmdevicestate ITCMFMDeviceState;    /* FORWARD */

int itcLevelThreadRunner(void *arg) ;

void handleKITCPacket(ITCMFMDeviceState * ds, u8 * packet, u32 len) ;

void updateKITC(ITCMFMDeviceState * ds) ;

#define MAX_MFZ_NAME_LENGTH 100
typedef u8 MFZId[MAX_MFZ_NAME_LENGTH + 1]; /* null-delimited 0..MAX_MFZ_NAME_LENGTH id string*/
typedef u8 MFMToken;                       /* random + incremented each id write, skipping 0 */
typedef u8 LevelStage;                     /*  + level:3 + stage:2 */

inline static u8 getLevelStageFromPacketByte(u8 packetByte) { return packetByte&0x1f; /*bottom five bits*/ }
inline static u8 getLevelFromLevelStage(LevelStage ls) { return (ls>>2)&0x7; }
inline static u8 getStageFromLevelStage(LevelStage ls) { return (ls>>0)&0x3; }
inline static u8 getLevelStageAsByte(LevelStage ls) { return (getLevelFromLevelStage(ls)<<4) | getStageFromLevelStage(ls); }

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
  DO_CONTINUE
} LevelAction;

/* Functions & pointers */
typedef bool        LevelRequire_func (ITCMFMDeviceState*);
typedef LevelAction LevelTimeout_func (ITCMFMDeviceState*, bool, u32*);
typedef u32         LevelPacketIO_func(ITCMFMDeviceState*, bool, char*, u32);
typedef LevelAction LevelDecide_func  (ITCMFMDeviceState*);
typedef bool        LevelAdvance_func  (ITCMFMDeviceState*);

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
} ITCLevelState_ops;

typedef struct {
  unsigned long mUTimeout;  /* Timeout for us, jiffies */
  unsigned long mTTimeout;  /* Timeout for them, jiffies */
  MFMToken   mTToken;       /* Last physics ID we got */
  LevelStage mTLastLS;      /* Last LevelStage from Them */
  MFZId      mTMFZId;       /* (Last) MFZId from Them */
  LevelStage mUCurrentLS;   /* Current LevelStage of Us */
  bool       mCompat;       /* True if Them and Us are known compatible */
} ITCLevelState;

void initITCLevelState(ITCLevelState * ils) ;
unsigned long itcLevelStateGetEarliestTimeout(ITCLevelState * ils);

extern ITCLevelState_ops ilsDEFAULTS;

#endif /*ITCMFM_H*/
