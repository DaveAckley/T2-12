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
  return mds->mITCState.mStateNumber;
}

static void setStateKITC(ITCMFMDeviceState * mds, StateNumber sn) {
  BUG_ON(!mds);
  BUG_ON(sn >= MAX_STATE_NUMBER);

  if (mds->mITCState.mStateNumber != sn) {
    ADD_ITC_EVENT(makeItcStateEnterEvent(mds->mDir6,sn));
    DBGPRINTK(DBG_MISC100,"%s: [%s] %s->%s\n",
              __FUNCTION__,
              getDir8Name(mapDir6ToDir8(mds->mDir6)),
              getStateName(mds->mITCState.mStateNumber),
              getStateName(sn));
  }

  mds->mITCState.mStateNumber = sn;
}

void setTimeoutKITC(ITCMFMDeviceState * mds, u32 jiffiesToWait) {
  ITCState * is;
  unsigned long oldTimeout, newTimeout;
  BUG_ON(!mds);

  is = &mds->mITCState;

  oldTimeout = is->mTimeout;
  newTimeout = jiffies + jiffiesToWait;

  is->mTimeout = newTimeout;

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
  ITCState * is;
  u32 oursn;

  BUG_ON(!ds);
  BUG_ON(!pm);
  pm->index = 0;
  pm->pktbuf = buf;
  pm->len =ITC_MAX_PACKET_SIZE;

  dir6 = ds->mDir6;
  dir8 = mapDir6ToDir8(dir6);
  is = &ds->mITCState;
  oursn = is->mStateNumber;
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
  return 0 == strncmp(mds->mITCState.mMFZIdUs,
                      mds->mITCState.mMFZIdThem,
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
static ITCSOps is##NAME = {             \
  .timeout = YY##CUSTO(NAME,timeout),   \
  .receive = YY##CUSRC(NAME,receive),   \
};

ALL_STATES_MACRO()

#undef YY0
#undef YY1
#undef XX


/*** DEFINE STATE DISPATCH ARRAY **/

#define XX(NAME,CUSTO,CUSRC,DESC)       \
  &is##NAME,                            \

static ITCSOps *(theStates[MAX_STATE_NUMBER]) = {
  ALL_STATES_MACRO()
};

#undef XX

ITCSOps * getOpsOrNull(StateNumber sn) {
  if (sn >= MAX_STATE_NUMBER) return 0;
  return theStates[sn];
}

/**** MISC HELPERS ****/

void wakeITCTimeoutRunner(void) {
  if (S.mKITCTimeoutThread.mThreadTask) 
    wake_up_process(S.mKITCTimeoutThread.mThreadTask);
  else
    printk(KERN_ERR "No S.mKITCTimeoutThread.mThreadTask?\n");
}

static inline void recvKITCPacket(ITCMFMDeviceState *ds, u8 * packet, u32 len)
{
  PacketHandler ph;
  u32 psn;
  ITCSOps * ops;
  BUG_ON(!ds);
  if (!initReadPacketHandler(&ph, packet, len))
    printk(KERN_ERR "%s illegal packet, len %d, ignored\n",
           __FUNCTION__,
           len);
  psn = getStateNumberFromPH(&ph);
  ADD_ITC_EVENT(makeItcStateReceiveEvent(ds->mDir6,ds->mITCState.mStateNumber));
  DBGPRINTK(DBG_KITC_PIO,"%s rc %s len=%d (us=[%s]%s)\n",
            __FUNCTION__,
            getStateName(psn),
            len,
            getDir8Name(mapDir6ToDir8(ds->mDir6)),
            getStateName(ds->mITCState.mStateNumber));

  ops = getOpsOrNull(psn); /* Dispatch on the packet type, not ds state! */
  BUG_ON(!ops);
  ops->receive(ds, &ph);
}

/*****************************/
/* PUBLIC FUNCTIONS */

void initITCState(ITCState * is)
{
  BUG_ON(!is);
  is->mTimeout = jiffies + (prandom_u32_max(50)+10);
  is->mToken = 0;
  is->mMFZIdUs[0] = '\0';
  is->mMFZIdThem[0] = '\0';
  is->mStateNumber = SN_INIT;
}

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

    /*XXX    ADD_ITC_EVENT(makeItcSpecEvent(IEV_SPEC_BITR)); */

    /** Find earliest timeout **/
    for (itcIteratorStart(itr); itcIteratorHasNext(itr); ) {
      ITCDir kitc = itcIteratorGetNext(itr);
      ITCMFMDeviceState * mds = s->mMFMDeviceState[kitc];
      ITCState * is = &mds->mITCState;
      if (ties==0 || time_before(is->mTimeout, earliestTime)) {
        earliestDir = kitc;
        earliestTime = is->mTimeout;
        ties = 1;
      } else if (is->mTimeout == earliestTime && prandom_u32_max(++ties) == 0) {
        earliestDir = kitc;
      }
    }

    /** Do it or sleep **/
    BUG_ON(ties==0);

    if (time_before(earliestTime, jiffies)) {

      /* Do it */
      ITCMFMDeviceState * mds = s->mMFMDeviceState[earliestDir];
      ITCState * is = &mds->mITCState;
      ITCSOps * ops = theStates[is->mStateNumber];
      BUG_ON(!ops);
      DBGPRINTK(DBG_MISC100,"%s: [%s] to %s\n",
                __FUNCTION__,
                getDir8Name(mapDir6ToDir8(mds->mDir6)),
                getStateName(is->mStateNumber));
      ADD_ITC_EVENT(makeItcStateTimeoutEvent(earliestDir,is->mStateNumber));
      initWritePacketHandler(&ph, mds);
      ops->timeout(mds,&ph);

    } else {

      /* Sleep */
      diffToNext = jiffiesFromAtoB(jiffies, earliestTime);
    
#if 0 /*XXX*/
      if (0) { /*COND*/ }
      else if (diffToNext < msToJiffies(5)) ADD_ITC_EVENT(makeItcSpecEvent(IEV_SPEC_SLP0));
      else if (diffToNext < msToJiffies(50)) ADD_ITC_EVENT(makeItcSpecEvent(IEV_SPEC_SLP1));
      else if (diffToNext < msToJiffies(500)) ADD_ITC_EVENT(makeItcSpecEvent(IEV_SPEC_SLP2));
      else ADD_ITC_EVENT(makeItcSpecEvent(IEV_SPEC_SLP3));
#endif      
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

static bool sendPacketHandler(PacketHandler * ph) {
  bool ret;
  BUG_ON(!ph);
  ret = trySendUrgentRoutedKernelPacket(ph->pktbuf,ph->index) > 0;

  ADD_ITC_EVENT(makeItcStateSendEvent(mapDir8ToDir6(getDir8FromPH(ph)),
                                       getStateNumberFromPH(ph)));
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
    u32 idx = readZstringFromPH(ph, mds->mITCState.mMFZIdThem, sizeof(MFZId));
    if (idx < sizeof(MFZId)) mds->mITCState.mMFZIdThem[idx] = '\0';
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
    u32 idx = readZstringFromPH(ph, mds->mITCState.mMFZIdThem, sizeof(MFZId));
    if (idx < sizeof(MFZId)) mds->mITCState.mMFZIdThem[idx] = '\0';
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
