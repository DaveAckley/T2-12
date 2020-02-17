#include "itcmfm.h"
#include "itcpkt.h"

/**** EARLY LEVEL HACKERY ****/

#define ALL_LEVELS_MACRO()                                    \
/*         name   cust req tmo, pio, dcd, adv, state (NOT USED) */ \
/* 0 */ XX(CONTACT,      1,  1,   1,   0,   1,            _)       \
/* 1 */ XX(COMMUNICATE,  1,  0,   1,   0,   0,   _/*u16 ttoken*/)  \
/* 2 */ XX(COMPATIBILITY,0,  0,   1,   1,   0, _/*MFZId tMFZId*/)  \
/* 3 */ XX(COMPUTATION,  0,  1,   0,   0,   1,            _)       \

/****/
/* Define level numbers */

#define XX(NAM,REQ,TMO,PIO,DCD,ADV,VAR)   \
  LEVEL_NUMBER_##NAM,
typedef enum levelnumber {
  ALL_LEVELS_MACRO()
  MAX_LEVEL_NUMBER
} LevelNumber;
#undef XX

ITCLSOps *(theLevels[MAX_LEVEL_NUMBER]);      /*FORWARD*/


/**** MISC HELPERS ****/

static unsigned long plusOrMinus25pct(u32 amt) {
  if (amt >= 8) {  /* don't randomize if too tiny */
    u32 delta = prandom_u32_max((amt>>1)+1); /*random in 0..amt/2 */
    amt += (delta - (amt>>2)); /* +-25% */
  }
  return amt;
}

static LevelStage itcGetOurLevelStage(ITCLevelState * ils)
{
  BUG_ON(!ils);
  return ils->mUs.mLevelStage;
}

static ITCLSOps * itcSideStateGetLevelOps(ITCSideState *ss)
{
  u32 level;
  BUG_ON(!ss);
  level = getLevelFromLevelStage(ss->mLevelStage);
  BUG_ON(level >= MAX_LEVEL_NUMBER);
  return theLevels[level];
}

static void wakeITCLevelRunner(void) {
  if (S.mKITCLevelThread.mThreadTask) 
    wake_up_process(S.mKITCLevelThread.mThreadTask);
  else
    printk(KERN_ERR "No S.mKITCLevelThread.mThreadTask?\n");
}

static unsigned long itcSideStateSetLastAnnounceToNow(ITCSideState *ss)
{
  unsigned long now = jiffies;
  ITCLSOps * ops = itcSideStateGetLevelOps(ss);
  u32 timeoutVar = 0;
  ops->timeout(0, ss->mIsUs, &timeoutVar);
  ss->mLastAnnounce = now;
  ss->mNextTimeout = now + plusOrMinus25pct(timeoutVar);
  DBGPRINTK(DBG_MISC200,"%s: timeoutVar=%d, now=%lu, nextTo=%lu\n",
            __FUNCTION__,
            timeoutVar,
            now,
            ss->mNextTimeout
            );
  wakeITCLevelRunner();
  return ss->mNextTimeout;
}

/**** LEVEL DEFAULTS ****/

static bool ilsRequireDefault(ITCMFMDeviceState* kitc) {
  printk(KERN_ERR "%s:%d WHY DON'T YOU WRITE ME\n",__FILE__,__LINE__);
  return true;
}

static LevelAction ilsTimeoutDefault(ITCMFMDeviceState* kitc, bool usNotThem, u32 *nextTimeoutPtr) {
  if (nextTimeoutPtr) 
    *nextTimeoutPtr = usNotThem ? 100 : 500;
  return usNotThem ? DO_REENTER : DO_RETREAT;
}

static u32 ilsPacketIODefault(ITCMFMDeviceState* kitc,
                              bool recvNotSend, u32 startIdx,
                              u8 *pkt, u32 len) {
  /* Exchange and Confirm Default: Nothing */
  return startIdx;
}

static LevelAction ilsDecideDefault(ITCMFMDeviceState* kitc) {
  /* Decide default: continue */
  return DO_CONTINUE;
}

static bool ilsAdvanceDefault(ITCMFMDeviceState* mds) {
  ITCLevelState * ils;
  LevelStage usLS;
  BUG_ON(!mds);
  ils = &mds->mLevelState;
  usLS = ils->mUs.mLevelStage;
  return
    ((ils->mThem.mLevelStage >= makeLevelStage(getLevelFromLevelStage(usLS),1)) &&
     getStageFromLevelStage(usLS) == 2);
}

ITCLSOps ilsDEFAULTS = {
  .require = ilsRequireDefault,
  .timeout = ilsTimeoutDefault,
  .packetio= ilsPacketIODefault,
  .decide  = ilsDecideDefault,
  .advance = ilsAdvanceDefault,
};


/**** LATE LEVEL HACKERY ****/

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

#define YY0(nm,type) ils##type##Default
#define YY1(nm,type) ils##type##_##nm
#define XX(NAM,REQ,TMO,PIO,DCD,ADV,VAR)         \
ITCLSOps ils##NAM = {       \
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

ITCLSOps *(theLevels[MAX_LEVEL_NUMBER]) = {
  ALL_LEVELS_MACRO()
};

#undef XX

/* End of define level dispatch array */


#if 0
static ITCLSOps * itcGetOurLevelOps(ITCLevelState * ils)
{
  BUG_ON(!ils);
  return itcSideStateGetLevelOps(&ils->mUs);
}
#endif

static inline void recvLevelPacket(ITCMFMDeviceState *ds, u8 * packet, u32 len)
{
  ITCLevelState * ils;
  u32 level, curLevel, index = 0;
  BUG_ON(!ds);
  ils = &ds->mLevelState;
  curLevel = getLevelFromLevelStage(ils->mUs.mLevelStage);
  DBGPRINTK(DBG_LVL_PIO,"recvLevelPacket us=L%02x them=L%02x, pkt=L%02x\n",
            getLevelStageAsByte(ils->mUs.mLevelStage),
            getLevelStageAsByte(ils->mThem.mLevelStage),
            getLevelStageAsByte(packet[1]));
  DBGPRINT_HEX_DUMP(DBG_LVL_PIO,
                    KERN_INFO, getDir8Name(mapDir6ToDir8(ds->mDir6)),
                    DUMP_PREFIX_OFFSET, 16, 1,
                    packet, len, true);
  for (level = 0; level <= curLevel; ++level) {
    ITCLSOps *ops = theLevels[level];
    BUG_ON(!ops);
    index = ops->packetio(ds, true, index, packet, len);
    if (index == 0) break; /* recv aborted */
  }
}

static inline void sendLevelPacket(ITCMFMDeviceState *ds, bool forceTimeoutPush)
{
  u8 buf[ITC_MAX_PACKET_SIZE+1];
  u32 level, curLevel, index = 0;
  u8 dir6;
  u8 dir8;
  ITCLevelState * ils;
  LevelStage ourLS;

  ssize_t ret = 0;
  BUG_ON(!ds);

  dir6 = ds->mDir6;
  dir8 = mapDir6ToDir8(dir6);
  ils = &ds->mLevelState;
  ourLS = itcGetOurLevelStage(ils);

  curLevel = getLevelFromLevelStage(ourLS);

#if 0 /*done by ilsPacketIO_CONTACT now*/
  buf[index++] = 0xa0|dir8;  /*standard+urgent to dir8*/
  buf[index++] = 0xc0|ourLS; /*mfm+itc+our levelstage*/
#endif

  for (level = 0; level <= curLevel; ++level) {
    ITCLSOps *ops = theLevels[level];
    BUG_ON(!ops);
    index = ops->packetio(ds, false, index, buf, ITC_MAX_PACKET_SIZE);
    if (index == 0) /*return 0 says abort packet send.. good?*/
      break;
  }

  DBGPRINTK(DBG_LVL_PIO,"sendLevelPacket us=L%02x them=L%02x, len=%d\n",
            getLevelStageAsByte(ils->mUs.mLevelStage),
            getLevelStageAsByte(ils->mThem.mLevelStage),
            index);
  DBGPRINT_HEX_DUMP(DBG_LVL_PIO,
                    KERN_INFO, getDir8Name(mapDir6ToDir8(ds->mDir6)),
                    DUMP_PREFIX_OFFSET, 16, 1,
                    buf, index, true);

  if (index > 0)
    ret = trySendUrgentRoutedKernelPacket(buf,index);

  if (ret == 0 || forceTimeoutPush) {
    itcSideStateSetLastAnnounceToNow(&ils->mUs);
  }
  if (ret != 0) {
    printk(KERN_INFO "sendLevelPacket (pushto=%s) hdr=0x%02x got %d\n",
           forceTimeoutPush ? "T" : "F",
           buf[0], ret);
  }

}

#if 0
static inline void pushTimeout(ITCMFMDeviceState * ds, bool usNotThem)
{
  unsigned long now = jiffies;
  u32 mswait = 0;
  ITCLevelState * ils;
  ITCLSOps * lops;

  BUG_ON(!ds);
  ils = &ds->mLevelState;
  lops = itcGetLevelOps(ils);

  BUG_ON(!lops);

  lops->timeout(ds,usNotThem,&mswait); /*return value ignored*/
  if (mswait == 0) {
    printk(KERN_ERR "timeout returned 0 increment\n");
    mswait = 100;
  }

  unsigned long newto = now + plusOrMinus25pct(mswait);
  ITCSideState * ss = usNotThem ? &ils->mUs : &8ls->mThem;
XXX DO WE HAVE TIMEOUT OR NOT?
  ss->mUTimeout = newto;
  else ils->mTTimeout = newto;

  /* we can never make the earliest timeout earlier,
     so we don't have to wake the timer thread. */
}
#endif


/*** LEVEL CUSTOMIZATIONS ***/

/****/
/* CONTACT */

static bool ilsRequire_CONTACT(ITCMFMDeviceState* kitc) {
  /*Require Default: No requirements*/
  return true;
}

static u32 ilsPacketIO_CONTACT(ITCMFMDeviceState* ds,
                              bool recvNotSend, u32 startIdx,
                              u8 *pkt, u32 len) {
  BUG_ON(!ds);
  BUG_ON(!pkt);
  BUG_ON(startIdx!=0);
  DBGPRINTK(DBG_LVL_PIO,"ilsPacketIO_CONTACT recv=%s startIdx=%d len=%d\n",
            recvNotSend ? "true" : "false",
            startIdx,
            len);

  if (recvNotSend) {
    u8 byte0, byte1;
    u8 dir8, dir6;
    ITCSideState * ss;

    if (startIdx + 2 > len) return 0; /* Can't read header?? */

    byte0 = pkt[startIdx++];
    byte1 = pkt[startIdx++];
    dir8 = byte0&0x7;
    dir6 = mapDir8ToDir6(dir8);
    
    if (((byte0 & 0xf0) != 0xa0) ||    /* standard+urgent */
        (dir6 != ds->mDir6) ||        /* our dir */
        ((byte1 & 0xc0) != 0xc0)) {   /* mfm+itc */
      printk(KERN_ERR "0x%02x%02x packet not right (got %d/us %d)\n",
             byte0,byte1,dir6,ds->mDir6);
      return 0;
    }
    
    /* Pick up their info*/
    ss = &ds->mLevelState.mThem;
    ss->mLevelStage = byte1 & 0x1f;
    itcSideStateSetLastAnnounceToNow(ss);

  } else {

    u8 dir6 = ds->mDir6;
    u8 dir8 = mapDir6ToDir8(dir6);
    ITCLevelState * ils = &ds->mLevelState;
    LevelStage ourLS = itcGetOurLevelStage(ils);
    BUG_ON(startIdx + 2 > len);

    if (!isITCEnabledStatusByDir8(dir8))  /* don't try without PS */
      return 0;

    pkt[startIdx++] = 0xa0|dir8;  /*standard+urgent to dir8*/
    pkt[startIdx++] = 0xc0|ourLS; /*mfm+itc+our levelstage*/
  }

  return startIdx;
}


static LevelAction ilsTimeout_CONTACT(ITCMFMDeviceState* kitc, bool usNotThem, u32 *nextTimeoutPtr) {
  if (nextTimeoutPtr) 
    *nextTimeoutPtr = 10000;
  return DO_RESTART;
}

static bool ilsAdvance_CONTACT(ITCMFMDeviceState* ds) {
  /* Advance on PACKET SYNC */
  u32 dir8;
  bool ret;
  BUG_ON(!ds);
  dir8 = mapDir6ToDir8(ds->mDir6);
  ret = isITCEnabledStatusByDir8(dir8);
  DBGPRINTK(DBG_MISC200,"(%s) %s: ret=%d\n",
            getDir8Name(dir8),
            __FUNCTION__,
            ret);
  return ret;
}

/****/
/* COMMUNICATE */

static bool ilsRequire_COMMUNICATE(ITCMFMDeviceState* ds) {
  /* Fail without PACKET SYNC */
  u32 dir8;
  bool ret;
  BUG_ON(!ds);
  dir8 = mapDir6ToDir8(ds->mDir6);
  ret = isITCEnabledStatusByDir8(dir8);
  return ret;
}

static u32 ilsPacketIO_COMMUNICATE(ITCMFMDeviceState* ds,
                                   bool recvNotSend, u32 startIdx,
                                   u8 *pkt, u32 len) {
  BUG_ON(!ds);
  BUG_ON(!pkt);
  BUG_ON(startIdx==0);
  DBGPRINTK(DBG_LVL_PIO,"%s recv=%s startIdx=%d len=%d\n",
            __FUNCTION__,
            recvNotSend ? "true" : "false",
            startIdx,
            len);
  return startIdx;
}


/****/
/* COMPATIBILITY */

static u32 ilsPacketIO_COMPATIBILITY(ITCMFMDeviceState* kitc,
                                     bool recvNotSend, u32 startIdx,
                                     u8 *pkt, u32 len) {
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

static void initITCSideState(ITCSideState * ss, bool isUs)
{
  unsigned long now = jiffies;
  BUG_ON(!ss);
  ss->mLastAnnounce = now - (prandom_u32_max(50)+(isUs ? 100 : 10));
  ss->mNextTimeout = now + (prandom_u32_max(50)+(isUs ? 10 : 100));
  ss->mToken = 0;
  ss->mMFZId[0] = '\0';
  ss->mLevelStage = 0;
  ss->mSeqno = 0;
  ss->mCompat = false;
  ss->mIsUs = isUs;
}

void initITCLevelState(ITCLevelState * ils)
{
  BUG_ON(!ils);
  initITCSideState(&ils->mUs, true);
  initITCSideState(&ils->mThem, false);
}

unsigned long itcSideStateGetTimeout(ITCSideState * ss)
{
  BUG_ON(!ss);
  return ss->mNextTimeout;
}

unsigned long itcLevelStateGetEarliestTimeout(ITCLevelState * ils)
{
  unsigned long uto, tto;
  BUG_ON(!ils);
  uto = itcSideStateGetTimeout(&ils->mUs);
  tto = itcSideStateGetTimeout(&ils->mThem);
  return time_before(uto, tto) ? uto : tto;
}

#define jiffyDiffy(au32,bu32) ((s32) ((au32)-(bu32)))
int itcLevelThreadRunner(void *arg)
{
  ITCKThreadState * ks = (ITCKThreadState*) arg;
  ITCModuleState * s = &S;
  ITCIterator * itr;
  BUG_ON(!ks);
  itr = &ks->mDir6Iterator;
  
  printk(KERN_INFO "itcLevelThreadRunner for %p: Started\n", s);

  set_current_state(TASK_RUNNING);
  while(!kthread_should_stop()) {    /* Returns true when kthread_stop() is called */
    unsigned long now = jiffies;
    s32 diffToNext = 0;
    for (itcIteratorStart(itr); itcIteratorHasNext(itr); ) {
      ITCDir kitc = itcIteratorGetNext(itr);
      ITCMFMDeviceState * mds = s->mMFMDeviceState[kitc];
      unsigned long timeout;
      s32 jiffiesTilTimeout;
      BUG_ON(!mds);
      timeout = itcLevelStateGetEarliestTimeout(&mds->mLevelState);
      DBGPRINTK(DBG_MISC100,"kitc=%d, timeout=%lu, now=%lu\n",kitc,timeout,now);
      if (time_after_eq(now, timeout)) {
        updateKITC(mds);
        /* XXX updateKITC has to handle this now: pushTimeout(mds,true); */
        timeout = itcLevelStateGetEarliestTimeout(&mds->mLevelState);
        if (timeout == now) ++timeout; /*can't be now*/
      }
      jiffiesTilTimeout = jiffyDiffy(timeout,now);
      DBGPRINTK(DBG_MISC100,"diffToNext=%d, jifTil=%d\n",diffToNext,jiffiesTilTimeout);
      if (diffToNext == 0 || diffToNext > jiffiesTilTimeout)
        diffToNext = jiffiesTilTimeout;
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

void handleKITCPacket(ITCMFMDeviceState * ds, u8 * packet, u32 len)
{
  BUG_ON(!ds);
  BUG_ON(!packet || len < 2);

  /* handle the packet */
  recvLevelPacket(ds,packet,len);
  
  /* then update their state machine*/
  updateKITC(ds);      
}

void updateKITC(ITCMFMDeviceState * mds)
{
  ITCLevelState * ils;
  ITCSideState * ss;
  u8 prevLS, newLS;
  u32 prevLevel, enterLevel;
  u32 prevStage, enterStage;
  u32 level;
  BUG_ON(!mds);
  DBGPRINTK(DBG_MISC200,"(%s) UPDATE KITC them=L%02x\n",
            getDir8Name(mapDir6ToDir8(mds->mDir6)),
            getLevelStageAsByte(mds->mLevelState.mThem.mLevelStage)
            );
  ils = &mds->mLevelState;
  ss = &ils->mUs;
  prevLS = ss->mLevelStage;
  prevLevel = enterLevel = getLevelFromLevelStage(prevLS);
  prevStage = enterStage = getStageFromLevelStage(prevLS);
  BUG_ON(prevLevel >= MAX_LEVEL_NUMBER);

  /****
     - update begins with requirements check.  Level requirements are
       cumulative.  If currently supported level < previous level, enter
       at currently supported level, stage 0.  Otherwise enter at previous
       level, previous stage.
  ****/
  for (level = 0; level <= prevLevel; ++level) {
    ITCLSOps *ops = theLevels[level];
    bool ret;
    DBGPRINTK(DBG_MISC200,"(%s) UPDATE reqmts level=%d, ops=%p\n",
              getDir8Name(mapDir6ToDir8(mds->mDir6)),
           level,
           ops);
    BUG_ON(!ops);
    BUG_ON(!ops->require);
    ret = (*ops->require)(mds);
    if (ret) continue; /* Level is supported */
    /*Level is not supported*/
    if (level < prevLevel) {
      enterLevel = level;
      enterStage = 0;
      break;
    }
  }
  DBGPRINTK(DBG_MISC200,"(%s) UPDATE post reqmts enterlevel=%d, enterstage=%d\n",
            getDir8Name(mapDir6ToDir8(mds->mDir6)),
            enterLevel,enterStage);

  /* Set entry level */
  newLS = makeLevelStage(enterLevel, enterStage);
  ss->mLevelStage = newLS;
  {
    /*** RUN .decide ***/
    u8 nextLS;
    ITCLSOps *ops = theLevels[enterLevel];
    LevelAction decideAction;
    BUG_ON(!ops);
    BUG_ON(!ops->decide);
    decideAction = (*ops->decide)(mds);
    DBGPRINTK(DBG_MISC200,"(%s) UPDATE ss->mLevelStage=L%02x decideAction=%d\n",
              getDir8Name(mapDir6ToDir8(mds->mDir6)),
              getLevelStageAsByte(ss->mLevelStage),
              decideAction);
    switch (decideAction) {
    case DO_REENTER:
      nextLS = makeLevelStage(enterLevel,0);
      break;
    case DO_RESTART:
      nextLS = makeLevelStage(0,0);
      break;
    case DO_RETREAT:
      if (enterLevel > 0) enterLevel--;
      nextLS = makeLevelStage(enterLevel, 0);
      break;
    case DO_ADVANCE:
      if (enterLevel < MAX_LEVEL_NUMBER-1) enterLevel++;
      nextLS = makeLevelStage(enterLevel, 0);
      break;
    case DO_CONTINUE:
      nextLS = makeLevelStage(enterLevel,enterStage);
      break;
    default: BUG_ON(1);
    }

  DBGPRINTK(DBG_MISC200,"(%s) MORE ME UPDATE newLS=L%02x nextls=L%02x\n",
            getDir8Name(mapDir6ToDir8(mds->mDir6)),
            getLevelStageAsByte(newLS),
            getLevelStageAsByte(nextLS));
  }
  {
    /*** RUN .advance ***/
    LevelStage curLS = ss->mLevelStage;
    LevelStage advanceLS;
    u8 curLevel = getLevelFromLevelStage(curLS);
    u8 curStage = getStageFromLevelStage(curLS);
    ITCLSOps *ops = theLevels[curLevel];
    bool ret;
    BUG_ON(!ops);
    BUG_ON(!ops->advance);
    ret = (*ops->advance)(mds);
    DBGPRINTK(DBG_MISC200,"(%s) UPDATE ss->mLevelStage=L%02x advance=%s\n",
              getDir8Name(mapDir6ToDir8(mds->mDir6)),
              getLevelStageAsByte(ss->mLevelStage),
              ret ? "true" : "false");
    if (ret) {
      if (curStage < 2) 
        advanceLS = makeLevelStage(curLevel, curStage+1);
      else if (curLevel < MAX_LEVEL_NUMBER-1)
        advanceLS = makeLevelStage(curLevel+1, 0);
      else
        advanceLS = curLS;
      if (advanceLS != curLS) {
        DBGPRINTK(DBG_LVL_LSC,"(%s) ADVANCING L%02x -> L%02x\n",
                  getDir8Name(mapDir6ToDir8(mds->mDir6)),
                  getLevelStageAsByte(curLS),
                  getLevelStageAsByte(advanceLS));
        ss->mLevelStage = advanceLS;
        sendLevelPacket(mds,false); /*pushes timeout if sent*/
      }
    }
  }
  {
    /**** REANNOUNCE IF WE HAVE TIMED OUT */
    unsigned long now = jiffies;
    unsigned long uto = itcSideStateGetTimeout(ss);
    if (time_after_eq(jiffies, uto)) {
      sendLevelPacket(mds,true); /*pushes timeout for sure*/
      DBGPRINTK(DBG_MISC200,"(%s) REANNOUNCED L%02x, now=%lu, uto=%lu, new=%lu\n",
                getDir8Name(mapDir6ToDir8(mds->mDir6)),
                getLevelStageAsByte(ss->mLevelStage),
                now,
                uto,
                itcSideStateGetTimeout(ss));
    }
  }

}

