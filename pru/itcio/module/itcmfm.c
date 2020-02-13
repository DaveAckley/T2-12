#include "itcmfm.h"
#include "itcpkt.h"

static bool ilsRequireDefault(ITCMFMDeviceState* kitc) {
  printk(KERN_ERR "%s:%d WHY DON'T YOU WRITE ME\n",__FILE__,__LINE__);
  return true;
}

static LevelAction ilsTimeoutDefault(ITCMFMDeviceState* kitc, bool usNotThem, u32 *nextTimeoutPtr) {
  if (nextTimeoutPtr) 
    *nextTimeoutPtr = usNotThem ? 100 : 500;
  return usNotThem ? DO_REENTER : DO_RETREAT;
}

static u32 ilsPacketIODefault(ITCMFMDeviceState* kitc, bool exchangeNotConfirm, char *pkt, u32 startIdx) {
  /* Exchange and Confirm Default: Nothing */
  return startIdx;
}

static LevelAction ilsDecideDefault(ITCMFMDeviceState* kitc) {
  /* Decide default: continue */
  return DO_CONTINUE;
}

static bool ilsAdvanceDefault(ITCMFMDeviceState* kitc) {
  printk(KERN_ERR "%s:%d WHY DON'T YOU WRITE ME\n",__FILE__,__LINE__);
  return false;
}

ITCLevelState_ops ilsDEFAULTS = {
  .require = ilsRequireDefault,
  .timeout = ilsTimeoutDefault,
  .packetio= ilsPacketIODefault,
  .decide  = ilsDecideDefault,
  .advance = ilsAdvanceDefault,
};

#define ALL_LEVELS_MACRO()                                    \
/*         name   cust req tmo, pio, dcd, adv, state (NOT USED) */ \
/* 0 */ XX(CONTACT,      1,  1,   0,   0,   1,            _)       \
/* 1 */ XX(COMMUNICATE,  1,  0,   1,   0,   0,   _/*u16 ttoken*/)  \
/* 2 */ XX(COMPATIBILITY,0,  0,   1,   1,   0, _/*MFZId tMFZId*/)  \
/* 3 */ XX(COMPUTATION,  0,  1,   0,   0,   1,            _)       \


/****/
/* Declare custom functions */

#define YY0(NM,TYPE) 
#define YY1(NM,TYPE) static Level##TYPE##_func ils##TYPE##_##NM;

#define XX(NAM,REQ,TMO,PIO,DCD,ADV,VAR)   \
  YY##REQ(NAM,Require)                \
  YY##TMO(NAM,Timeout)                \
  YY##PIO(NAM,PacketIO)               \
  YY##DCD(NAM,Decide)                 \
  YY##ADV(NAM,Advance)                \

ALL_LEVELS_MACRO();

#undef YY0
#undef YY1
#undef XX

/* End of declare custom functions */
/****/


/****/
/* Declare ops tables */

#define YY0(nm,type) 0
#define YY1(nm,type) ils##type##_##nm
#define XX(NAM,REQ,TMO,PIO,DCD,ADV,VAR)         \
ITCLevelState_ops ils##NAM = {       \
  .require = YY##REQ(NAM,Require),   \
  .timeout = YY##TMO(NAM,Timeout),   \
  .packetio= YY##PIO(NAM,PacketIO),  \
  .decide  = YY##DCD(NAM,Decide),    \
  .advance = YY##ADV(NAM,Advance),   \
};

ALL_LEVELS_MACRO();

#undef YY0
#undef YY1
#undef XX

/* End of declare ops tables */

/****/
/* Define level dispatch array */

#define XX(NAM,REQ,TMO,PIO,DCD,ADV,VAR)         \
  &ils##NAM,                                    \

ITCLevelState_ops *(theLevels[]) = {
  ALL_LEVELS_MACRO()
  0
};

#undef XX

/* End of define level dispatch array */


/*** LEVEL CUSTOMIZATIONS ***/

/****/
/* CONTACT */

static bool ilsRequire_CONTACT(ITCMFMDeviceState* kitc) {
  /*Require Default: No requirements*/
  return true;
}

static LevelAction ilsTimeout_CONTACT(ITCMFMDeviceState* kitc, bool usNotThem, u32 *nextTimeoutPtr) {
  if (nextTimeoutPtr) 
    *nextTimeoutPtr = 10000;
  return DO_RESTART;
}

static bool ilsAdvance_CONTACT(ITCMFMDeviceState* ds) {
  /* Advance on PACKET SYNC */
  u32 dir8;
  BUG_ON(!ds);
  dir8 = mapDir6ToDir8(ds->mDir6);
  return isITCEnabledStatusByDir8(dir8);
}

/****/
/* COMMUNICATE */

static bool ilsRequire_COMMUNICATE(ITCMFMDeviceState* kitc) {
  printk(KERN_ERR "%s:%d WHY DON'T YOU WRITE ME\n",__FILE__,__LINE__);
  return true;
}

static u32 ilsPacketIO_COMMUNICATE(ITCMFMDeviceState* kitc, bool exchangeNotConfirm, char *pkt, u32 startIdx) {
  printk(KERN_ERR "%s:%d WHY DON'T YOU WRITE ME\n",__FILE__,__LINE__);
  return startIdx;
}


/****/
/* COMPATIBILITY */

static u32 ilsPacketIO_COMPATIBILITY(ITCMFMDeviceState* kitc, bool exchangeNotConfirm, char *pkt, u32 startIdx) {
  printk(KERN_ERR "%s:%d WHY DON'T YOU WRITE ME\n",__FILE__,__LINE__);
  return startIdx;
}

static LevelAction ilsDecide_COMPATIBILITY(ITCMFMDeviceState* kitc) {
  printk(KERN_ERR "%s:%d WHY DON'T YOU WRITE ME\n",__FILE__,__LINE__);
  return DO_CONTINUE;
}


/****/
/* COMPUTATION */

static LevelAction ilsTimeout_COMPUTATION(ITCMFMDeviceState* kitc, bool usNotThem, u32 *nextTimeoutPtr) {
  if (nextTimeoutPtr) 
    *nextTimeoutPtr = usNotThem ? 10000 : 50000;
  return usNotThem ? DO_REENTER : DO_RETREAT;
}

static bool ilsAdvance_COMPUTATION(ITCMFMDeviceState* kitc) {
  /*Last level, never advance */
  return false;
}


/*****************************/
/* PUBLIC FUNCTIONS */

void initITCLevelState(ITCLevelState * ils)
{
  unsigned long now = jiffies;
  BUG_ON(!ils);
  ils->mUTimeout = now + prandom_u32_max(50)+10;
  ils->mTTimeout = ils->mUTimeout + prandom_u32_max(50)+100;
  ils->mTToken = 0;
  ils->mTLastLS = 0;
  ils->mTMFZId[0] = '\0';
  ils->mUCurrentLS = 0;
  ils->mCompat = false;
}

unsigned long itcLevelStateGetEarliestTimeout(ITCLevelState * ils)
{
  BUG_ON(!ils);
  return time_before(ils->mUTimeout, ils->mTTimeout) ? ils->mUTimeout : ils->mTTimeout;
}


#define jiffyDiffy(au32,bu32) ((s32) ((au32)-(bu32)))
int itcLevelThreadRunner(void *arg)
{
  ITCModuleState * s = &S;
  BUG_ON(!s);
  
  printk(KERN_INFO "itcLevelThreadRunner for %p: Started\n", s);

  set_current_state(TASK_RUNNING);
  while(!kthread_should_stop()) {    /* Returns true when kthread_stop() is called */
    unsigned kitc;
    unsigned long now = jiffies;
    s32 diffToNext = 0;
    for (kitc = 0; kitc < MFM_MINORS; ++kitc) {
      ITCMFMDeviceState * mds = s->mMFMDeviceState[kitc];
      unsigned long timeout;
      BUG_ON(!mds);
      timeout = itcLevelStateGetEarliestTimeout(&mds->mLevelState);
      DBGPRINTK(DBG_MISC100,"kitc=%d, timeout=%lu, now=%lu\n",kitc,timeout,now);
      if (time_after_eq(timeout, now))
        updateKITC(mds);
      else {
        s32 jiffiesTilTimeout = jiffyDiffy(timeout,now);
        DBGPRINTK(DBG_MISC100,"diffToNext=%d, jifTil=%d\n",diffToNext,jiffiesTilTimeout);
        if (diffToNext == 0 || diffToNext > jiffiesTilTimeout)
          diffToNext = jiffiesTilTimeout;
      }
    }
    DBGPRINTK(DBG_MISC100,"final diffToNext=%d\n",diffToNext);
    if (diffToNext == 0) diffToNext = HZ/2; /* Really?  Nothing coming up at all?  Go 500ms */
    diffToNext = HZ/2; /*XXX WTF?*/
    set_current_state(TASK_INTERRUPTIBLE);
    schedule_timeout(diffToNext);   /* in TASK_RUNNING again upon return */
  }
  printk(KERN_INFO "itcLevelThreadRunner: Stopping by request\n");
  return 0;
}

static ITCLevelState_ops * itcGetLevelOps(ITCLevelState * ils)
{
  u32 level;
  BUG_ON(!ils);
  level = getLevelFromLevelStage(ils->mUCurrentLS);
  BUG_ON(level >= sizeof(theLevels)/sizeof(theLevels[0]));
  return theLevels[level];
}

void handleKITCPacket(ITCMFMDeviceState * ds, u8 * packet, u32 len)
{
  u8 type;
  ITCLevelState * ils;
  //  LevelStage theirLS;

  BUG_ON(!ds);
  BUG_ON(!packet || len < 2);
  ils = &ds->mLevelState;
  type = packet[0];
  /*stash their last/latest LS*/
  ils->mTLastLS = getLevelStageFromPacketByte(packet[1]);
  /*we heard (something) from them, update their timeout
    BUT: do we do this before or after level code sees the packet??
   */
  {
    unsigned long now = jiffies;
    u32 mswait = 0;
    ITCLevelState_ops * lops = itcGetLevelOps(ils);
    BUG_ON(!lops);
    lops->timeout(ds,false,&mswait);
    if (mswait == 0) {
      printk(KERN_ERR "timeout returned 0 increment\n");
      mswait = 100;
    }
    DBGPRINTK(DBG_MISC100,"PRE ttimout=%lu, mswait=%d\n",ils->mTTimeout, mswait);
    if (mswait >= 8) {
      u32 delta = prandom_u32_max(mswait>>1); /*random in 50% */
      mswait = mswait + (delta - (mswait>>2)); /* +-25% */
    }
    ils->mTTimeout = now + mswait;
    DBGPRINTK(DBG_MISC100,"PST ttimout=%lu, mswait=%d, now=%lu\n",ils->mTTimeout, mswait,now);
  }
  DBGPRINTK(DBG_MISC200,"(%s) HANDLE KITC TRAFFIC HERE NOW (%d) them=%02x\n",
            getDir8Name(type&0x7),
            len,
            getLevelStageAsByte(packet[1])
            );
}

void updateKITC(ITCMFMDeviceState * kitc)
{
  ITCLevelState * ls;
  u32 curLevel;
  u32 curStage;
  u32 level;
  BUG_ON(!kitc);
  printk(KERN_INFO "(%s) UPDATE KITC them=L%02x\n",
         getDir8Name(mapDir6ToDir8(kitc->mDir6)),
         getLevelStageAsByte(kitc->mLevelState.mTLastLS)
         );
  ls = &kitc->mLevelState;
  curLevel = getLevelFromLevelStage(ls->mUCurrentLS);
  curStage = getStageFromLevelStage(ls->mUCurrentLS);

  /****
     - update begins with requirements check.  Level requirements are
       cumulative.  If currently supported level < previous level, enter
       at currently supported level, stage 0.  Otherwise enter at previous
       level, previous stage.
  ****/
  for (level = 0; level <= curLevel; ++level) {
    ITCLevelState_ops *ops = theLevels[level];
    bool ret;
    BUG_ON(!ops);
    ret = (*ops->require)(kitc);
  }

}
