#include "itcmfm.h"
#include "itcpkt.h"

const char * getStateName(StateNumber sn) ; /*FORWARD*/

static StateNumber getStateNumberFromPH(PacketHandler * ph) {
  BUG_ON(!ph);
  BUG_ON(ph->len < 2);
  return ph->pktbuf[1]&0xf;
}

static u8 getDir8FromPH(PacketHandler * ph) {
  BUG_ON(!ph);
  BUG_ON(ph->len < 1);
  return ph->pktbuf[0]&0x7;
}

static StateNumber getStateKITC(ITCMFMDeviceState *mds) {
  BUG_ON(!mds);
  return mds->mLevelState.mUs.mStateNumber;
}

static void setStateKITC(ITCMFMDeviceState * mds, StateNumber sn) {
  BUG_ON(!mds);
  BUG_ON(sn >= MAX_STATE_NUMBER);

  if (mds->mLevelState.mUs.mStateNumber != sn) {
    DBGPRINTK(DBG_MISC100,"%s: [%s] %s->%s\n",
              __FUNCTION__,
              getDir8Name(mapDir6ToDir8(mds->mDir6)),
              getStateName(mds->mLevelState.mUs.mStateNumber),
              getStateName(sn));
  }

  mds->mLevelState.mUs.mStateNumber = sn;
}

void setTimeoutKITC(ITCMFMDeviceState * mds, u32 jiffiesToWait) {
  ITCLevelState * ils;
  unsigned long oldTimeout, newTimeout;
  BUG_ON(!mds);

  ils = &mds->mLevelState;

  oldTimeout = ils->mUs.mTimeout;
  newTimeout = jiffies + jiffiesToWait;

  ils->mUs.mTimeout = newTimeout;

  if (time_before(newTimeout,oldTimeout)) /* If we moved a timeout earlier, the */
    wakeITCTimeoutRunner();               /* timeout runner needs a fresh look */
}

static bool initReadPacketHandler(PacketHandler * pm, u8 * data, u32 len) {
  BUG_ON(!pm);
  BUG_ON(!data);
  pm->pktbuf = data;
  pm->len = len;
  if (len < 2) return false;
  
  if ((pm->pktbuf[0]&~0x7) != 0xa0) return false;
  if ((pm->pktbuf[1]&~0xf) != 0xc0) return false;
  if ((pm->pktbuf[1]&0xf) >= MAX_STATE_NUMBER) return false;

  pm->index = 2;
  return true;
}

static s32 readByteFromPH(PacketHandler * ph)
{
  BUG_ON(!ph);
  if (ph->index >= ph->len) return -1;
  return (s32) ph->pktbuf[ph->index++];
}

static u32 readZstringFromPH(PacketHandler * ph, u8 * dest, u32 len)
{
  u32 i = 0;
  s32 ch;
  while ((ch = readByteFromPH(ph)) > 0) {
    if (i < len) dest[i++] = (u8) ch;
  }
  return i;
}

static void initWritePacketHandler(PacketHandler * pm, ITCMFMDeviceState *ds)
{
  static u8 buf[ITC_MAX_PACKET_SIZE+1];
  u8 dir6;
  u8 dir8;
  ITCLevelState * ils;
  u32 oursn;

  BUG_ON(!ds);
  BUG_ON(!pm);
  pm->index = 0;
  pm->pktbuf = buf;
  pm->len =ITC_MAX_PACKET_SIZE;

  dir6 = ds->mDir6;
  dir8 = mapDir6ToDir8(dir6);
  ils = &ds->mLevelState;
  oursn = ils->mUs.mStateNumber;
  BUG_ON(oursn > 0xf);       /* Only 4 bits for sn */

  pm->pktbuf[pm->index++] = 0xa0|dir8;  /*standard+urgent to dir8*/
  pm->pktbuf[pm->index++] = 0xc0|oursn; /*mfm+itc+our statenumber*/
}

static void writeByteToPH(PacketHandler * ph, u8 byte)
{
  BUG_ON(!ph);
  BUG_ON(ph->index >= ph->len);
  ph->pktbuf[ph->index++] = byte;
}

static void writeZstringToPH(PacketHandler * ph, const u8 * zstr)
{
  u8 ch;
  do {
    ch = *zstr++;
    writeByteToPH(ph, ch);   /* include trailing '\0' */
  } while (ch);              
}

static bool compatibleMFZId(ITCMFMDeviceState *mds) {
  BUG_ON(!mds);
  return 0 == strncmp(mds->mLevelState.mUs.mMFZId,
                      mds->mLevelState.mThem.mMFZId,
                      MAX_MFZ_NAME_LENGTH);
}

/**** LATE STATES HACKERY ****/

/*** STATE NAMES AS STRING **/
const char * stateName[] = {
#define XX(NAME,CUSTO,CUSRC,DESC) #NAME,
  ALL_STATES_MACRO()
#undef XX
  "?ILLEGAL"
};

const char * getStateName(StateNumber sn) {
  if (sn >= MAX_STATE_NUMBER) return "illegal";
  return stateName[sn];
}

/*** STATE DESCRIPTIONS AS STRING **/
const char * stateDesc[] = {
#define XX(NAME,CUSTO,CUSRC,DESC) #DESC,
  ALL_STATES_MACRO()
#undef XX
  "?ILLEGAL"
};

const char * getStateDescription(StateNumber sn) {
  if (sn >= MAX_STATE_NUMBER) return "illegal";
  return stateDesc[sn];
}

/*** DECLARE DEFAULT AND CUSTOM TIMEOUT HANDLERS **/
#define YY0(NAME) void timeoutDefault_KITC(ITCMFMDeviceState * mds, PacketHandler * ph) ;
#define YY1(NAME) void timeout_##NAME##_KITC(ITCMFMDeviceState * mds, PacketHandler * ph) ;
#define XX(NAME,CUSTO,CUSRC,DESC) YY##CUSTO(NAME)
  ALL_STATES_MACRO()
#undef XX
#undef YY1
#undef YY0

/*** DECLARE DEFAULT AND CUSTOM PACKET RECEIVE HANDLERS **/
#define YY0(NAME) void receiveDefault_KITC(ITCMFMDeviceState * mds, PacketHandler * ph) ;
#define YY1(NAME) void receive_##NAME##_KITC(ITCMFMDeviceState * mds, PacketHandler *ph) ;
#define XX(NAME,CUSTO,CUSRC,DESC) YY##CUSRC(NAME)
  ALL_STATES_MACRO()
#undef XX
#undef YY1
#undef YY0


/*** DECLARE OPS TABLES **/

#define YY0(nm,type) type##Default_KITC
#define YY1(nm,type) type##_##nm##_KITC
#define XX(NAME,CUSTO,CUSRC,DESC)       \
static ITCLSOps ils##NAME = {           \
  .timeout = YY##CUSTO(NAME,timeout),   \
  .receive = YY##CUSRC(NAME,receive),   \
};

ALL_STATES_MACRO()

#undef YY0
#undef YY1
#undef XX


/*** DEFINE STATE DISPATCH ARRAY **/

#define XX(NAME,CUSTO,CUSRC,DESC)       \
  &ils##NAME,                           \

static ITCLSOps *(theStates[MAX_STATE_NUMBER]) = {
  ALL_STATES_MACRO()
};

#undef XX

ITCLSOps * getOpsOrNull(StateNumber sn) {
  if (sn >= MAX_STATE_NUMBER) return 0;
  return theStates[sn];
}



/**** MISC HELPERS ****/

#if 0
static unsigned long plusOrMinus25pct(u32 amt) {
  if (amt >= 8) {  /* don't randomize if too tiny */
    u32 delta = prandom_u32_max((amt>>1)+1); /*random in 0..amt/2 */
    amt += (delta - (amt>>2)); /* +-25% */
  }
  return amt;
}

static StateNumber itcGetOurStateNumber(ITCLevelState * ils)
{
  BUG_ON(!ils);
  return ils->mUs.mStateNumber;
}

static ITCLSOps * itcSideStateGetLevelOps(ITCSideState *ss)
{
  u32 sn;
  BUG_ON(!ss);
  sn = ss->mStateNumber;
  BUG_ON(sn >= MAX_STATE_NUMBER);
  return theStates[sn];
}
#endif

void wakeITCTimeoutRunner(void) {
  if (S.mKITCTimeoutThread.mThreadTask) 
    wake_up_process(S.mKITCTimeoutThread.mThreadTask);
  else
    printk(KERN_ERR "No S.mKITCTimeoutThread.mThreadTask?\n");
}

#if 0
static unsigned long itcSideStateTouch(ITCSideState *ss)
{
  unsigned long now = jiffies;
  ITCLSOps * ops = itcSideStateGetLevelOps(ss);
  u32 timeoutVar = 0;
  u32 fuzzedTimeoutVar;
  ss->mTimeoutAction = ops->timeout(0, ss->mIsUs, &timeoutVar);
  fuzzedTimeoutVar = plusOrMinus25pct(timeoutVar);
  ss->mModTime = now;
  ss->mNextTimeout = now + fuzzedTimeoutVar;
  ADD_ITC_EVENT(makeItcSpecEvent(ss->mIsUs? IEV_SPEC_PTOU : IEV_SPEC_PTOT));
  DBGPRINTK(DBG_MISC200,"%s: %s=L%02x TO=%d[%d], now=%lu, nextTo=%lu\n",
            __FUNCTION__,
            ss->mIsUs ? "mUs" : "mThem",
            getLevelStageAsByte(ss->mLevelStage),
            timeoutVar,
            fuzzedTimeoutVar,
            now,
            ss->mNextTimeout
            );
  wakeITCLevelRunner();
  return ss->mNextTimeout;
}
#endif

static inline void recvKITCPacket(ITCMFMDeviceState *ds, u8 * packet, u32 len)
{
  PacketHandler ph;
  u32 psn;
  ITCLSOps * ops;
  BUG_ON(!ds);
  if (!initReadPacketHandler(&ph, packet, len))
    printk(KERN_ERR "%s illegal packet, len %d, ignored\n",
           __FUNCTION__,
           len);
  psn = getStateNumberFromPH(&ph);

  DBGPRINTK(DBG_KITC_PIO,"%s rc %s len=%d (us=[%s]%s)\n",
            __FUNCTION__,
            getStateName(psn),
            len,
            getDir8Name(mapDir6ToDir8(ds->mDir6)),
            getStateName(ds->mLevelState.mUs.mStateNumber));

  ops = getOpsOrNull(psn); /* Dispatch on the packet type, not ds state! */
  BUG_ON(!ops);
  ops->receive(ds, &ph);
}

#if 0
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
    itcSideStateTouch(&ils->mUs);
  }
  if (ret != 0) {
    printk(KERN_INFO "sendLevelPacket (pushto=%s) hdr=0x%02x got %d\n",
           forceTimeoutPush ? "T" : "F",
           buf[0], ret);
  }

}
#endif

/*****************************/
/* PUBLIC FUNCTIONS */

static void initITCSideState(ITCSideState * ss, bool isUs)
{
  BUG_ON(!ss);
  ss->mTimeout = jiffies + (prandom_u32_max(50)+(isUs ? 10 : 100));
  ss->mToken = 0;
  ss->mMFZId[0] = '\0';
  ss->mStateNumber = SN_INIT;
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
  return ss->mTimeout;
}

#if 0
unsigned long itcLevelStateGetEarliestTimeout(ITCLevelState * ils)
{
  unsigned long uto, tto;
  BUG_ON(!ils);
  uto = itcSideStateGetTimeout(&ils->mUs);
  tto = itcSideStateGetTimeout(&ils->mThem);
  return time_before(uto, tto) ? uto : tto;
}
#endif

#define jiffiesFromAtoB(au32,bu32) ((s32) ((bu32)-(au32)))
int kitcTimeoutThreadRunner(void *arg)
{
  static PacketHandler ph;
  ITCKThreadState * ks = (ITCKThreadState*) arg;
  ITCModuleState * s = &S;
  ITCIterator * itr;
  BUG_ON(!ks);
  itr = &ks->mDir6Iterator;
  
  printk(KERN_INFO "%s for %p: Started\n", __func__, s);

  set_current_state(TASK_RUNNING);
  while(!kthread_should_stop()) {    /* Returns true when kthread_stop() is called */
    unsigned long earliestTime;
    ITCDir earliestDir;
    u32 ties = 0;
    s32 diffToNext;

    ADD_ITC_EVENT(makeItcSpecEvent(IEV_SPEC_BITR));

    /** Find earliest timeout **/
    for (itcIteratorStart(itr); itcIteratorHasNext(itr); ) {
      ITCDir kitc = itcIteratorGetNext(itr);
      ITCMFMDeviceState * mds = s->mMFMDeviceState[kitc];
      ITCLevelState * ils = &mds->mLevelState;
      ITCSideState * us = &ils->mUs;
      if (ties==0 || time_before(us->mTimeout, earliestTime)) {
        earliestDir = kitc;
        earliestTime = us->mTimeout;
        ties = 1;
      } else if (us->mTimeout == earliestTime && prandom_u32_max(++ties) == 0) {
        earliestDir = kitc;
      }
    }

    /** Do it or sleep **/
    BUG_ON(ties==0);

    if (time_before(earliestTime, jiffies)) {

      /* Do it */
      ITCMFMDeviceState * mds = s->mMFMDeviceState[earliestDir];
      ITCLevelState * ils = &mds->mLevelState;
      ITCLSOps * ops = theStates[ils->mUs.mStateNumber];
      BUG_ON(!ops);
      DBGPRINTK(DBG_MISC100,"%s: [%s] to %s\n",
                __FUNCTION__,
                getDir8Name(mapDir6ToDir8(mds->mDir6)),
                getStateName(mds->mLevelState.mUs.mStateNumber));

      initWritePacketHandler(&ph, mds);
      ops->timeout(mds,&ph);

    } else {

      /* Sleep */
      diffToNext = jiffiesFromAtoB(jiffies, earliestTime);
    
      if (0) { /*COND*/ }
      else if (diffToNext < msToJiffies(5)) ADD_ITC_EVENT(makeItcSpecEvent(IEV_SPEC_SLP0));
      else if (diffToNext < msToJiffies(50)) ADD_ITC_EVENT(makeItcSpecEvent(IEV_SPEC_SLP1));
      else if (diffToNext < msToJiffies(500)) ADD_ITC_EVENT(makeItcSpecEvent(IEV_SPEC_SLP2));
      else ADD_ITC_EVENT(makeItcSpecEvent(IEV_SPEC_SLP3));
      
      set_current_state(TASK_INTERRUPTIBLE);
      schedule_timeout(diffToNext);   /* in TASK_RUNNING again upon return */
    }
  }
  printk(KERN_INFO "%s: Stopping by request\n",__FUNCTION__);
  return 0;
}

void handleKITCPacket(ITCMFMDeviceState * ds, u8 * packet, u32 len)
{
  BUG_ON(!ds);
  BUG_ON(!packet || len < 2);

  /* handle the packet */
  recvKITCPacket(ds,packet,len);
  
}

#if 0
typedef LevelStage (*LSEvaluator)(ITCMFMDeviceState * mds, LevelStage prevls) ;
static LevelStage lsEvaluatorSupport(ITCMFMDeviceState * mds, LevelStage prevls) ;
static LevelStage lsEvaluatorUTimeout(ITCMFMDeviceState * mds, LevelStage prevls) ;
static LevelStage lsEvaluatorTTimeout(ITCMFMDeviceState * mds, LevelStage prevls) ;
static LevelStage lsEvaluatorDecide(ITCMFMDeviceState * mds, LevelStage prevls) ;
static LevelStage lsEvaluatorAdvance(ITCMFMDeviceState * mds, LevelStage prevls) ;

static LSEvaluator lsEvals[] = {
  &lsEvaluatorSupport,
  &lsEvaluatorUTimeout,
  &lsEvaluatorTTimeout,
  &lsEvaluatorDecide,
  &lsEvaluatorAdvance
};

void updateKITC(ITCMFMDeviceState * mds)
{
  ITCLevelState * ils;
  ITCSideState * ss;
  LevelStage prevLS, nextLS;
  u32 i;

  BUG_ON(!mds);
  ADD_ITC_EVENT(makeItcDirEvent(mds->mDir6,IEV_DIR_UPBEG));
  DBGPRINTK(DBG_MISC200,"(%s) >>>UPDATE KITC us=L%02x them=L%02x\n",
            getDir8Name(mapDir6ToDir8(mds->mDir6)),
            getLevelStageAsByte(mds->mLevelState.mUs.mLevelStage),
            getLevelStageAsByte(mds->mLevelState.mThem.mLevelStage)
            );
  ils = &mds->mLevelState;
  ss = &ils->mUs;
  prevLS = ss->mLevelStage;
  for (i = 0; i < sizeof(lsEvals)/sizeof(lsEvals[0]); ++i) {
    LSEvaluator eval = lsEvals[i];
    nextLS = (*eval)(mds,prevLS);
    DBGPRINTK(DBG_MISC200,"(%s) LSE[%d] prevLS=L%02x -> nextLS=L%02x\n",
              getDir8Name(mapDir6ToDir8(mds->mDir6)),
              i,
              getLevelStageAsByte(prevLS),
              getLevelStageAsByte(nextLS)
              );
    if (nextLS != prevLS) break; /* found a move, stop */
  }
  if (nextLS != prevLS) {
    ss->mLevelStage = nextLS;

    ADD_ITC_EVENT(makeItcLSEvent(mds->mDir6,IEV_LSU,ss->mLevelStage));

    sendLevelPacket(mds,false); /*pushes timeout if sent*/
  }
  
  DBGPRINTK(DBG_MISC200,"(%s) <<<END UPDATE KITC us=L%02x them=L%02x\n",
            getDir8Name(mapDir6ToDir8(mds->mDir6)),
            getLevelStageAsByte(mds->mLevelState.mUs.mLevelStage),
            getLevelStageAsByte(mds->mLevelState.mThem.mLevelStage)
            );
  ADD_ITC_EVENT(makeItcDirEvent(mds->mDir6,IEV_DIR_UPEND));
}

static LevelStage lsEvaluatorSupport(ITCMFMDeviceState * mds, LevelStage prevLS)
{
  ITCLevelState * ils;
  ITCSideState * ss;
  LevelStage newLS;
  u32 level, prevLevel;
  BUG_ON(!mds);
  DBGPRINTK(DBG_MISC200,"(%s) %s us=L%02x them=L%02x\n",
            getDir8Name(mapDir6ToDir8(mds->mDir6)),
            __FUNCTION__,
            getLevelStageAsByte(mds->mLevelState.mUs.mLevelStage),
            getLevelStageAsByte(mds->mLevelState.mThem.mLevelStage)
            );
  ils = &mds->mLevelState;
  ss = &ils->mUs;
  newLS = prevLS; /*assume just carry through*/
  prevLevel = getLevelFromLevelStage(newLS);

  /****
     - update begins with requirements check.  Level requirements are
       cumulative.  If currently supported level < previous level, enter
       at currently supported level, stage 0.  Otherwise enter at previous
       level, previous stage.
  ****/
  for (level = 0; level <= prevLevel; ++level) {
    ITCLSOps *ops = theLevels[level];
    bool ret;
    BUG_ON(!ops);
    BUG_ON(!ops->require);
    ret = (*ops->require)(mds);
    DBGPRINTK(DBG_MISC200,"(%s) %s reqmts level=%d, prevLevel=%d, ret=%d\n",
              getDir8Name(mapDir6ToDir8(mds->mDir6)),
              __FUNCTION__,
              level,
              prevLevel,
              ret);
    if (ret) continue; /* Level is supported */
    /*Level is not supported*/
    if (level > 0) { /* If we have any place to fall */
      newLS = makeLevelStage(level - 1, 0);  /* drop back to previous level */
      break;
    }
  }
  DBGPRINTK(DBG_MISC200,"(%s) %s newLS=0x%02x\n",
            getDir8Name(mapDir6ToDir8(mds->mDir6)),
            __FUNCTION__,
            getLevelStageAsByte(newLS));
  return newLS;
}

static LevelStage applyLevelActionToLevelStage(LevelAction action, LevelStage ls)
{
  u32 prevLevel = getLevelFromLevelStage(ls);
  LevelStage newLS = ls;
  
  switch (action) {
  case DO_REENTER:
    newLS = makeLevelStage(prevLevel,0);
    break;
  case DO_RESTART:
    newLS = makeLevelStage(0,0);
    break;
  case DO_RETREAT:
    if (prevLevel > 0) prevLevel--;
    newLS = makeLevelStage(prevLevel, 0);
    break;
  case DO_ADVANCE:
    if (prevLevel < MAX_LEVEL_NUMBER-1) prevLevel++;
    newLS = makeLevelStage(prevLevel, 0);
    break;
  default:
    printk(KERN_ERR "%s illegal action %d ignored\n",
           __FUNCTION__,
           action);
    /*FALL THROUGH*/
  case DO_CONTINUE:
    break;
  }
  DBGPRINTK(DBG_MISC200,"%s(%d, L%02x)->L%02x\n",
            __FUNCTION__,
            action,
            getLevelStageAsByte(ls),
            getLevelStageAsByte(newLS)
            );
  return newLS;
}

static LevelStage ssEvaluatorCheckTimeout(ITCSideState * ss, LevelStage prevLS)
{
  LevelStage newLS = prevLS;
  unsigned long uto;
  BUG_ON(!ss);
  uto = itcSideStateGetTimeout(ss);
  if (time_after_eq(jiffies, uto)) {
    newLS = applyLevelActionToLevelStage(ss->mTimeoutAction,prevLS);
    itcSideStateTouch(ss);
  }
  return newLS;
}

static LevelStage lsEvaluatorUTimeout(ITCMFMDeviceState * mds, LevelStage prevLS)
{
  ITCLevelState * ils;
  ITCSideState * ss;
  BUG_ON(!mds);
  ils = &mds->mLevelState;
  ss = &ils->mUs;
  return ssEvaluatorCheckTimeout(ss, prevLS);
}

static LevelStage lsEvaluatorTTimeout(ITCMFMDeviceState * mds, LevelStage prevLS)
{
  ITCLevelState * ils;
  ITCSideState * ss;
  BUG_ON(!mds);
  ils = &mds->mLevelState;
  ss = &ils->mThem;
  return ssEvaluatorCheckTimeout(ss, prevLS);
}

static LevelStage lsEvaluatorDecide(ITCMFMDeviceState * mds, LevelStage prevLS)
{
  ITCLevelState * ils;
  ITCSideState * ss;
  LevelStage newLS;
  u32 prevLevel;
  ITCLSOps *ops;
  LevelAction decideAction;

  BUG_ON(!mds);
  ils = &mds->mLevelState;
  ss = &ils->mThem;
  newLS = prevLS; /*assume just carry through*/
  prevLevel = getLevelFromLevelStage(newLS);

  ops = theLevels[prevLevel];
  
  BUG_ON(!ops);
  BUG_ON(!ops->decide);
  decideAction = (*ops->decide)(mds);

  DBGPRINTK(DBG_MISC200,"(%s) %s ss->mLevelStage=L%02x decideAction=%d\n",
            getDir8Name(mapDir6ToDir8(mds->mDir6)),
            __FUNCTION__,
            getLevelStageAsByte(ss->mLevelStage),
            decideAction);

  newLS = applyLevelActionToLevelStage(decideAction, prevLS);

  DBGPRINTK(DBG_MISC200,"(%s) %s prevLS=L%02x newls=L%02x\n",
            getDir8Name(mapDir6ToDir8(mds->mDir6)),
            __FUNCTION__,
            getLevelStageAsByte(prevLS),
            getLevelStageAsByte(newLS));
  return newLS;
}

static LevelStage lsEvaluatorAdvance(ITCMFMDeviceState * mds, LevelStage prevLS)
{
  /*** RUN .advance ***/
  LevelStage curLS = prevLS;
  LevelStage advanceLS = curLS; /*assume no advance*/
  u8 curLevel = getLevelFromLevelStage(curLS);
  u8 curStage = getStageFromLevelStage(curLS);
  ITCLSOps *ops = theLevels[curLevel];
  bool ret;
  BUG_ON(!ops);
  BUG_ON(!ops->advance);
  ret = (*ops->advance)(mds);
  DBGPRINTK(DBG_MISC200,"(%s) %s UPDATE prevLS=L%02x advance=%s\n",
            getDir8Name(mapDir6ToDir8(mds->mDir6)),
            __FUNCTION__,
            getLevelStageAsByte(prevLS),
            ret ? "true" : "false");
  if (ret) {
    if (curStage < 2) 
      advanceLS = makeLevelStage(curLevel, curStage+1);
    else if (curLevel < MAX_LEVEL_NUMBER-1)
      advanceLS = makeLevelStage(curLevel+1, 0);
  }
  if (advanceLS != curLS) {
    DBGPRINTK(DBG_LVL_LSC,"(%s) ADVANCING L%02x -> L%02x\n",
              getDir8Name(mapDir6ToDir8(mds->mDir6)),
              getLevelStageAsByte(curLS),
              getLevelStageAsByte(advanceLS));
  }
  return advanceLS;
}
#endif

static bool sendPacketHandler(PacketHandler * ph) {
  bool ret;
  BUG_ON(!ph);
  ret = trySendUrgentRoutedKernelPacket(ph->pktbuf,ph->index) > 0;

  DBGPRINTK(DBG_KITC_PIO,"sendKITCPacket pkt=%s len=%d (src=%s)\n",
            getStateName(getStateNumberFromPH(ph)),
            ph->index,
            getDir8Name(getDir8FromPH(ph)));
  return ret;
}

void resetKITC(ITCMFMDeviceState * mds) {
  setStateKITC(mds,SN_WAITPS);  /* On reset, first (re)check for packet sync */
  setTimeoutKITC(mds, jiffiesToWait(WC_RANDOM));
}

void receiveDefault_KITC(ITCMFMDeviceState * mds, PacketHandler * ph)
{
  resetKITC(mds); 
}

void timeoutDefault_KITC(ITCMFMDeviceState * mds, PacketHandler * ph)
{
  resetKITC(mds); 
}

/*** CUSTOM STATE HANDLERS ***/

/**STATE WAITPS**/
void timeout_WAITPS_KITC(ITCMFMDeviceState * mds, PacketHandler * ph)
{
  BUG_ON(!mds);
  if (isITCEnabledStatusByDir8(mapDir6ToDir8(mds->mDir6)))
    setStateKITC(mds, SN_LEAD); /*w/o pushing timeout, so goes immediately*/
  else
    setTimeoutKITC(mds, jiffiesToWait(WC_LONG));
}


/**STATE LEAD**/
void timeout_LEAD_KITC(ITCMFMDeviceState * mds, PacketHandler * ph)
{
  setStateKITC(mds, SN_WLEAD);
  setTimeoutKITC(mds, jiffiesToWait(WC_FULL));
  sendPacketHandler(ph);
}

void receive_LEAD_KITC(ITCMFMDeviceState * mds, PacketHandler *ph)
{
  StateNumber sn = getStateKITC(mds);
  if (sn == SN_WLEAD &&              /* race detected */
      prandom_u32_max(2)) {          /* flip coin */
    resetKITC(mds);
  } else {
    setStateKITC(mds, SN_FOLLOW);
    setTimeoutKITC(mds, jiffiesToWait(WC_HALF));
  }
}

/**STATE FOLLOW**/
void timeout_FOLLOW_KITC(ITCMFMDeviceState * mds, PacketHandler * ph)
{
  setStateKITC(mds, SN_WFOLLOW);
  setTimeoutKITC(mds, jiffiesToWait(WC_FULL));
  sendPacketHandler(ph);
}

void receive_FOLLOW_KITC(ITCMFMDeviceState * mds, PacketHandler *ph)
{
  StateNumber sn = getStateKITC(mds);
  if (sn != SN_WLEAD) {          /* messed up unless we're WLEAD */
    resetKITC(mds);
  } else {
    setStateKITC(mds, SN_CONFIG);
    setTimeoutKITC(mds, jiffiesToWait(WC_HALF));
  }
}

/**STATE CONFIG**/
void timeout_CONFIG_KITC(ITCMFMDeviceState * mds, PacketHandler * ph)
{
  MFMTileState * ts = &S.mMFMTileState;
  writeZstringToPH(ph, ts->mMFZId);

  setStateKITC(mds, SN_WCONFIG);
  setTimeoutKITC(mds, jiffiesToWait(WC_FULL));
  sendPacketHandler(ph);
}

void receive_CONFIG_KITC(ITCMFMDeviceState * mds, PacketHandler *ph)
{
  StateNumber sn = getStateKITC(mds);
  if (sn != SN_WFOLLOW) {          /* messed up unless we're WFOLLOW */
    resetKITC(mds);
  } else {
    u32 idx = readZstringFromPH(ph, mds->mLevelState.mThem.mMFZId, sizeof(MFZId));
    if (idx < sizeof(MFZId)) mds->mLevelState.mThem.mMFZId[idx] = '\0';
    setStateKITC(mds, SN_CHECK);
    setTimeoutKITC(mds, jiffiesToWait(WC_HALF));
  }
}

/**STATE CHECK**/
void timeout_CHECK_KITC(ITCMFMDeviceState * mds, PacketHandler * ph)
{
  MFMTileState * ts = &S.mMFMTileState;
  writeZstringToPH(ph, ts->mMFZId);
  setStateKITC(mds, compatibleMFZId(mds) ? SN_COMPATIBLE : SN_INCOMPATIBLE);
  setTimeoutKITC(mds, jiffiesToWait(WC_FULL));
  sendPacketHandler(ph);
}

void receive_CHECK_KITC(ITCMFMDeviceState * mds, PacketHandler *ph)
{
  StateNumber sn = getStateKITC(mds);
  if (sn != SN_WCONFIG) {
    resetKITC(mds);
  } else {
    u32 idx = readZstringFromPH(ph, mds->mLevelState.mThem.mMFZId, sizeof(MFZId));
    if (idx < sizeof(MFZId)) mds->mLevelState.mThem.mMFZId[idx] = '\0';
    setStateKITC(mds, compatibleMFZId(mds) ? SN_COMPATIBLE : SN_INCOMPATIBLE);
    setTimeoutKITC(mds, jiffiesToWait(WC_HALF));
  }
}

/**helpers for (in)compatible**/
void timeoutIn_or_Compatible_KITC(ITCMFMDeviceState * mds, PacketHandler * ph)
{
  BUG_ON(!mds || !ph);
  setTimeoutKITC(mds, jiffiesToWait(WC_LONG));
  sendPacketHandler(ph);
}

void receiveIn_or_Compatible_KITC(ITCMFMDeviceState * mds, PacketHandler *ph)
{
  StateNumber sn, psn;
  BUG_ON(!mds || !ph);

  sn = getStateKITC(mds);
  psn = ph->pktbuf[1]&0xf;
  if (sn != psn) resetKITC(mds);
  setTimeoutKITC(mds, jiffiesToWait(WC_LONG));
}

/**STATE COMPATIBLE, INCOMPATIBLE**/
void timeout_COMPATIBLE_KITC(ITCMFMDeviceState * mds, PacketHandler * ph)
{  timeoutIn_or_Compatible_KITC(mds,ph);  }

void receive_COMPATIBLE_KITC(ITCMFMDeviceState * mds, PacketHandler *ph)
{  receiveIn_or_Compatible_KITC(mds, ph);  }

void timeout_INCOMPATIBLE_KITC(ITCMFMDeviceState * mds, PacketHandler * ph)
{  timeoutIn_or_Compatible_KITC(mds,ph);  }

void receive_INCOMPATIBLE_KITC(ITCMFMDeviceState * mds, PacketHandler *ph)
{  receiveIn_or_Compatible_KITC(mds, ph);  }
