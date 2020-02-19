/*
 * Copyright (C) 2017 The Regents of the University of New Mexico
 *
 * This software is licensed under the terms of the GNU General Public
 * License version 2, as published by the Free Software Foundation, and
 * may be copied, distributed, and modified under those terms.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 */

#include "itcpkt.h"
#include "itcmfm.h"

static bool shipCurrentOBPackets(void) ;

static void tpReportIfMatch(TracePoint *tp, const char * tag, bool insert, char * pkt, int len, ITCPacketBuffer * ipb) ;
static void tpReportPkt(const char * tag, bool insert, char * pkt, int len, ITCPacketBuffer * ipb) ;

static void tppInitForOutput(TracePointParser *tpp, char *buf, u32 len) ;
static bool tppGeneratePatternIfNeeded(TracePointParser *tpp, TracePoint *tp) ;
static bool tppPutByte(TracePointParser * tpp, u8 ch) ;

static __printf(5,6) int sendMsgToPRU(unsigned prunum,
                                      unsigned wait,
                                      char * buf,
                                      unsigned bufsiz,
                                      const char * fmt, ...);


/** Actually returns ITCPRUDeviceState * or ITCPktDeviceState * */
static ITCCharDeviceState * makeITCCharDeviceState(struct device * dev,
                                                   unsigned struct_size,
                                                   int minor_obtained,
                                                   int * err_ret);


/* define MORE_DEBUGGING to be more verbose and slow*/
//#define MORE_DEBUGGING 1

#ifndef MORE_DEBUGGING
#define MORE_DEBUGGING 0
#endif

ITCModuleState S;               /* Our module-global state */

/** WARNING: RETURNS DIR8_COUNT ON UNKNWON PRU/PRUDIR COMBOS **/
static u32 mapPruAndPrudirToDir8(int pru, int prudir) {
  switch ((pru<<3)|prudir) {
#define XX(dir)                                                         \
  case (DIR_NAME_TO_PRU(dir)<<3) | DIR_NAME_TO_PRUDIR(dir): return DIR_NAME_TO_DIR8(dir);
FOR_XX_IN_ITC_ALL_DIR
#undef XX
  default: return DIR8_COUNT;
  }
}

#define STRPKTHDR_BUF_SIZE 8
#define STRPKTHDR_MAX_BUFS 10
static char * strPktHdr(u8 hdr) {
  static char buf[STRPKTHDR_BUF_SIZE][STRPKTHDR_MAX_BUFS];
  static u32 nextbuf = STRPKTHDR_MAX_BUFS;
  char * p = &buf[0][nextbuf];
  if (++nextbuf >= STRPKTHDR_MAX_BUFS) nextbuf = 0;
  
  if (isprint(hdr) && !(hdr&0x80))
    sprintf(p,"0x%02x'%c'",hdr,hdr);
  else
    sprintf(p,"0x%02x",hdr);
  return p;
}

static char * strMinor(int minor) {
  switch(minor) {
  case 0: return "pru0";
  case 1: return "pru1";
  case 2: return "pkt2";
  case 3: return "mfm3";
  default: BUG_ON(1);
  }
}

static char * strBuffer(int buffer) {
  switch(buffer) {
  case BUFFERSET_U: return "UserIB";
  case BUFFERSET_L: return "LoclIB";
  case BUFFERSET_P: return "PrioOB";
  case BUFFERSET_B: return "BulkOB";
  default: BUG_ON(1);
  }
}

static void initITCTrafficCounts(ITCTrafficCounts *c)
{
  c->mBytesSent = 0;
  c->mBytesReceived = 0;
  c->mPacketsSent = 0;
  c->mPacketsReceived = 0;
}

static void initITCTrafficStats(ITCTrafficStats *s, int dir)
{
  int i;
  s->mDirNum = dir;
  s->mPacketSyncAnnouncements = 0;
  s->mSyncFailureAnnouncements = 0;
  s->mTimeoutAnnouncements = 0;
  for (i = 0; i < TRAFFIC_COUNT_TYPES; ++i)
    initITCTrafficCounts(&s->mCounts[i]);
}

static ITCTrafficStats * getITCTrafficStatsFromDir8(u32 dir8)
{
  BUG_ON(dir8 >= DIR8_COUNT);
  return &S.mItcStats[dir8];
}

/** RETURNS 0 on illegal pru/prudir */
static ITCTrafficStats * getITCTrafficStats(u8 pru, u8 prudir)
{
  u32 dir8 = mapPruAndPrudirToDir8(pru,prudir);
  if (dir8 >= DIR8_COUNT) return 0;
  return getITCTrafficStatsFromDir8(dir8);
}

///////////////////// PACKET EVENT TRACING STUFF
static void initITCPktEventState(ITCPktEventState * pes) {
  BUG_ON(!pes);
  pes->mStartTime = 0;
  pes->mShiftDistance = 10;  /* divide by 1024 -> ~usec resolution */
  INIT_KFIFO(pes->mEvents);
  mutex_init(&pes->mPktEventReadMutex);
  printk(KERN_INFO "ZERGINI: initITCPktEventState(%p/%d), mutex(%p/%d), kfifo(%p/%d)\n",
         pes, sizeof(*pes),
         &pes->mPktEventReadMutex, sizeof(pes->mPktEventReadMutex),
         &pes->mEvents,sizeof(pes->mEvents));
}

static int startPktEventTrace(ITCPktEventState* pes) {
  int error;

  if ( (error = mutex_lock_interruptible(&pes->mPktEventReadMutex)) ) return error;  
  pes->mStartTime = ktime_get_raw_fast_ns();  /* Init time before making room in kfifo! */
  kfifo_reset_out(&pes->mEvents);             /* Flush kfifo from the read side */
  mutex_unlock(&pes->mPktEventReadMutex);

  return 0;
}

/*MUST BE CALLED ONLY AT INTERRUPT LEVEL OR WITH INTERRUPTS DISABLED*/
void addPktEvent(ITCPktEventState* pes, u32 event) {
  ITCPktEvent tmp;
  u64 now = ktime_get_raw_fast_ns() - pes->mStartTime;
  tmp.time = (u32) (now>>pes->mShiftDistance); // Cut down to u23
  /*
  printk(KERN_INFO "addPktEvent(%p,%08x) kfifo %p, now %lld, time = %d\n",
         pes,
         event,
         &pes->mEvents,
         now,
         tmp.time);
  */
  if (kfifo_avail(&pes->mEvents) >= 2*sizeof(ITCPktEvent)) tmp.event = event;
  else tmp.event = makeSpecPktEvent(PKTEVT_SPEC_QGAP);

  kfifo_put(&pes->mEvents, tmp);

  /*printk(KERN_INFO "addPktEvent done\n");*/
}

static void wakeOBPktShipper(void) {
  if (S.mOBPktThread.mThreadTask) 
    wake_up_process(S.mOBPktThread.mThreadTask);
  else
    printk(KERN_ERR "No S.mShipOBPktTask?\n");
}

static int itcOBPktThreadRunner(void *arg) {

  printk(KERN_INFO "itcOBPktThreadRunner: Started\n");

  set_current_state(TASK_RUNNING);
  while(!kthread_should_stop()) {    /* Returns true when kthread_stop() is called */
    int waitJiffies = HZ/2;          /* producers kick us so timeout should be rare backstop */
    if (shipCurrentOBPackets()) waitJiffies = 2; /* Except short wait if txbufs ran out or bulk pkts pending */
    set_current_state(TASK_INTERRUPTIBLE);
    schedule_timeout(waitJiffies);   /* in TASK_RUNNING again upon return */
  }
  printk(KERN_INFO "itcOBPktThreadRunner: Stopping by request\n");
  return 0;
}

static void initMFMTileState(MFMTileState *ts)
{
  ts->mMFMPid = -1;              /* No pid has written config to us */
  ts->mToken = 0;                /* So we've never initialized our token */
  ts->mMFZId[0] = '\0';          /* And our null-terminated id is empty */
}

static void initITCModuleState(ITCModuleState *s)
{
  {
    unsigned i;
    for (i = 0; i < PRU_MINORS; ++i) s->mPRUDeviceState[i] = 0;
    for (i = 0; i < PKT_MINORS; ++i) s->mPktDeviceState[i] = 0;
    for (i = 0; i < EVT_MINORS; ++i) s->mEvtDeviceState[i] = 0;
    for (i = 0; i < MFM_MINORS; ++i) s->mMFMDeviceState[i] = 0;
    for (i = 0; i < DIR8_COUNT; ++i) initITCTrafficStats(&s->mItcStats[i], i);
  }

  initMFMTileState(&s->mMFMTileState);

#if MORE_DEBUGGING
  s->mDebugFlags = 0xf; /* some default debugging */
#else
  s->mDebugFlags = 0;  /* or no default debugging */
#endif

  s->mOpenPRUMinors = 0;
  s->mItcEnabledStatus = 0;  // Assume all dirs disabled
}

static void createITCThread(ITCKThreadState * ts,
                            int (*funcptr)(void*),
                            ITCIteratorUseCount avguses,
                            const char * name)
{
  BUG_ON(!ts);
  init_waitqueue_head(&ts->mWaitQueue);
  itcIteratorInitialize(&ts->mDir6Iterator,avguses);
  
  ts->mThreadTask = kthread_run(funcptr, (void*) ts, name);

  if (IS_ERR(ts->mThreadTask)) 
    printk(KERN_ALERT "ITC: %s Thread creation failed\n",name);
  else
    printk(KERN_INFO "ITC: Created thread %s %p\n",name, ts->mThreadTask);
}

static void createITCThreads(ITCModuleState *s)
{
  createITCThread(&s->mOBPktThread,    itcOBPktThreadRunner,5000,"ITC_PktShipr");
  createITCThread(&s->mKITCLevelThread,itcLevelThreadRunner,5000,"KITC_LvlRunr");
}

static void destroyITCThread(ITCKThreadState *ts) {
  BUG_ON(!ts->mThreadTask);
  kthread_stop(ts->mThreadTask);
  ts->mThreadTask = 0;
}

static void destroyITCThreads(ITCModuleState *s) {
  destroyITCThread(&s->mKITCLevelThread);
  destroyITCThread(&s->mOBPktThread);
}

static inline int bytesInITCPacketBuffer(ITCPacketBuffer * ipb) {
  return kfifo_len(&ipb->mFIFO);
}

static inline int bulkOutboundBytesToPRUDev(ITCPRUDeviceState * prudev) {
  return bytesInITCPacketBuffer(&prudev->mBulkOB);
}

/* return size of packet sent, 0 if nothing to send, < 0 if problem */
static int sendPacketViaRPMsg(ITCPRUDeviceState * prudev, ITCPacketBuffer * ipb) {
  struct rpmsg_device * rpdev;
  int kfifolen, pktlen, ret;
  BUG_ON(!prudev || !ipb);

  kfifolen = kfifo_len(&ipb->mFIFO);
  if (kfifolen == 0) return 0;        /* Nothing to send */

  pktlen = kfifo_peek_len(&ipb->mFIFO);
  if (pktlen == 0) {
    printk(KERN_ERR "Empty pkt? OB kfifolen = %d but pktlen = %d (kfifo %p, prudev %p)\n",
           kfifolen,
           pktlen,
           &ipb->mFIFO,
           prudev);
    BUG_ON(1);
  }

  if (0 == kfifo_out_peek(&ipb->mFIFO, prudev->mTempPacketBuffer, RPMSG_MAX_PACKET_SIZE)) {
    /*
      printk(KERN_ERR "OB pktlen %d but kfifo_out_peek returned 0 (kfifo %p, prudev %p)\n",
           pktlen,
           &ipb->mFIFO,
           prudev);
    */

    return 0; /* Pretend there's nothing to send?? */
    //return -EBADSLT;
  }

  rpdev = prudev->mRpmsgDevice;
  BUG_ON(!rpdev);

  ret = rpmsg_trysend(rpdev->ept, prudev->mTempPacketBuffer, pktlen);

  if (ret == 0) 
    ADD_PKT_EVENT(makePktXfrEvent(PEV_XFR_TO_PRU, ipb->mPriority, log2in3(pktlen), prudev->mTempPacketBuffer[0]&0x7));

  DBGPRINTK(DBG_PKT_ROUTE,
            KERN_INFO "%d from trysend %s/%d pkt (kfln %d) via prudev %s %s\n",
            ret,
            strPktHdr(prudev->mTempPacketBuffer[0]),
            pktlen,
            kfifolen,
            prudev->mCDevState.mName,
            ipb->mName);

  if (ret < 0) {
    if (ret != -ENOMEM) {
      DBGPRINTK(DBG_PKT_SENT,
                KERN_INFO "Failure %d when trying to send %s/%d packet via prudev %s %s\n",
                ret,
                strPktHdr(prudev->mTempPacketBuffer[0]),
                pktlen,
                prudev->mCDevState.mName,
                ipb->mName);

    }
    return ret;      /* send failed; -ENOMEM means no tx buffers */
  }

  tpReportIfMatch(&ipb->mTraceRemove, prudev->mCDevState.mName, false, prudev->mTempPacketBuffer, pktlen, ipb);

  if (ipb->mRouted) { /* Do stats on routed buffers */
    u8 dir8 = prudev->mTempPacketBuffer[0]&0x7;  /* Get direction from header */
    ITCTrafficStats * t = getITCTrafficStatsFromDir8(dir8);
    u32 index = ipb->mPriority ? TRAFFIC_URGENT : TRAFFIC_BULK;
    BUG_ON(!t);
    ++t->mCounts[index].mPacketsSent;
    t->mCounts[index].mBytesSent += pktlen;
  }

  DBGPRINT_HEX_DUMP(DBG_PKT_SENT,
                    KERN_INFO, ">pru: ",
                    DUMP_PREFIX_NONE, 16, 1,
                    prudev->mTempPacketBuffer, pktlen, true);


  kfifo_skip(&ipb->mFIFO);           /* send succeeded, toss packet */
  wake_up_interruptible(&ipb->mWriterQ); /* and kick somebody if they were waiting to write */

  return pktlen;
}

/* return 0 if a priority packet shipped, 1 if a bulk packet shipped, or errno < 0 if problem */
static int shipAPacketToPRU(ITCPRUDeviceState * prudevstate) {
  int ret;
  BUG_ON(!prudevstate);
  BUG_ON(!prudevstate->mRpmsgDevice);

  ret = sendPacketViaRPMsg(prudevstate, &prudevstate->mPriorityOB);
  if (ret > 0) return 0;  /* shipped priority */
  if (ret < 0) return ret; /* problem */

  ret = sendPacketViaRPMsg(prudevstate, &prudevstate->mBulkOB);
  if (ret > 0) return 1;  /* shipped bulk */
  if (ret < 0) return ret; /* problem */

  return -ENODATA;     /* nothing to ship anywhere */
}

/* Advance OB packet shipping as far as immediately possible */
static bool shipCurrentOBPackets(void) {
  bool packetsWaiting = false;
  unsigned i;
  unsigned idx = prandom_u32_max(2);

  for (i = 0; i < 2; ++i, idx = 1-idx) {
    int ret;
    while ( (ret = shipAPacketToPRU(S.mPRUDeviceState[idx])) == 0 ) { /* empty */ }
    if (ret == -ENOMEM || bulkOutboundBytesToPRUDev(S.mPRUDeviceState[idx]) > 0)
        packetsWaiting = true;
  }

  return packetsWaiting;
}



__printf(5,6) int sendMsgToPRU(unsigned prunum,
                               unsigned wait,
                               char * buf,
                               unsigned bufsiz,
                               const char * fmt, ...)
{
  int ret = 0;
  unsigned len;
  va_list args;
  ITCPRUDeviceState * prudevstate;
  ITCPacketBuffer * localib;

  BUG_ON(prunum > 1);

  prudevstate = S.mPRUDeviceState[prunum];
  BUG_ON(!prudevstate);

  localib = &prudevstate->mLocalIB;

  BUG_ON(!prudevstate->mRpmsgDevice);

  va_start(args, fmt);
  len = vsnprintf(buf, bufsiz, fmt, args);
  va_end(args);

  if (len >= bufsiz) {
    printk(KERN_WARNING "send_msg_to_pru data (%d) exceeded bufsiz (%d) (type='%c') truncated\n",
           len, bufsiz, buf[0]);
  }

  if (len >= RPMSG_MAX_PACKET_SIZE) {
    printk(KERN_WARNING "send_msg_to_pru overlength (%d) packet (type='%c') truncated\n",
           len, buf[0]);
    len = RPMSG_MAX_PACKET_SIZE - 1;
  }

  if (mutex_lock_interruptible(&localib->mLock))
    return -ERESTARTSYS;

  DBGPRINT_HEX_DUMP(DBG_PKT_SENT,
                    KERN_INFO, prunum ? ">pru1: " : ">pru0: ",
                    DUMP_PREFIX_NONE, 16, 1,
                    buf, len, true);

  ret = rpmsg_send(prudevstate->mRpmsgDevice->ept, buf, len);

  /* Wait, if we're supposed to, for a packet in our kfifo */
  if (wait) {
    ITCPacketFIFO * kfifop = &localib->mFIFO;

    while (kfifo_is_empty(kfifop)) {
      if (wait_event_interruptible(localib->mReaderQ, !kfifo_is_empty(kfifop))) {
        ret = -ERESTARTSYS;
        break;
      }
    }

    if (ret == 0)
      if (!kfifo_out(kfifop, buf, bufsiz))
        printk(KERN_WARNING "kfifo was empty\n");
  }

  mutex_unlock(&localib->mLock);
  return ret;
}


/*CLASS ATTRIBUTE STUFF*/
static ssize_t poke_store(struct class *c,
			  struct class_attribute *attr,
			  const char *buf,
			  size_t count)
{
  unsigned poker;
  if (sscanf(buf,"%u",&poker) == 1) {
    printk(KERN_INFO "store poke %u\n",poker);
    return count;
  }
  return -EINVAL;
}
CLASS_ATTR_WO(poke);

static ssize_t status_show(struct class *c,
			   struct class_attribute *attr,
			   char *buf)
{
  sprintf(buf,"%08x\n",S.mItcEnabledStatus);
  return strlen(buf);
}
CLASS_ATTR_RO(status);

static ssize_t statistics_show(struct class *c,
			       struct class_attribute *attr,
			       char *buf)
{
  /* We have a PAGE_SIZE (== 4096) in buf, but won't get near that.  Max size
     presently is something like ( 110 + 8 * ( 2 + 3 * 11 + 8 * 11) ) < 1100 */
  int len = 0;
  int itc, speed;
  len += sprintf(&buf[len], "dir psan sfan toan blkbsent blkbrcvd blkpsent blkprcvd urgbsent urgbrcvd urgpsent urgprcvd\n");
  for (itc = 0; itc < DIR8_COUNT; ++itc) {
    ITCTrafficStats * t = &S.mItcStats[itc];
    len += sprintf(&buf[len], "%u %u %u %u",
                   itc,
                   t->mPacketSyncAnnouncements,
                   t->mSyncFailureAnnouncements,
                   t->mTimeoutAnnouncements
                   );
    for (speed = 0; speed < TRAFFIC_COUNT_TYPES; ++speed) {
      ITCTrafficCounts *c = &t->mCounts[speed];
      len += sprintf(&buf[len], " %u %u %u %u",
                     c->mBytesSent, c->mBytesReceived,
                     c->mPacketsSent, c->mPacketsReceived);
    }
    len += sprintf(&buf[len], "\n");
  }
  return len;
}
CLASS_ATTR_RO(statistics);

static ssize_t trace_start_time_show(struct class *c,
				     struct class_attribute *attr,
				     char *buf)
{
  sprintf(buf,"%lld\n",S.mEvtDeviceState[0]->mPktEvents.mStartTime);
  return strlen(buf);
}
CLASS_ATTR_RO(trace_start_time);

static ssize_t itc_trace_start_time_show(struct class *c,
				     struct class_attribute *attr,
				     char *buf)
{
  sprintf(buf,"%lld\n",S.mEvtDeviceState[1]->mPktEvents.mStartTime);
  return strlen(buf);
}
CLASS_ATTR_RO(itc_trace_start_time);

static ssize_t shift_show(struct class *c,
			  struct class_attribute *attr,
			  char *buf)
{
  sprintf(buf,"%d\n",S.mEvtDeviceState[0]->mPktEvents.mShiftDistance);
  return strlen(buf);
}

static ssize_t itc_shift_show(struct class *c,
			  struct class_attribute *attr,
			  char *buf)
{
  sprintf(buf,"%d\n",S.mEvtDeviceState[1]->mPktEvents.mShiftDistance);
  return strlen(buf);
}

static ssize_t shift_store(struct class *c,
			   struct class_attribute *attr,
			   const char *buf,
			   size_t count)
{
  u32 shift;
  if (sscanf(buf,"%u",&shift) == 1 && shift < 64) {
    printk(KERN_INFO "store shift %u\n",shift);
    S.mEvtDeviceState[0]->mPktEvents.mShiftDistance = shift;
    return count;
  }
  return -EINVAL;
}

static ssize_t itc_shift_store(struct class *c,
			   struct class_attribute *attr,
			   const char *buf,
			   size_t count)
{
  u32 shift;
  if (sscanf(buf,"%u",&shift) == 1 && shift < 64) {
    printk(KERN_INFO "store shift %u\n",shift);
    S.mEvtDeviceState[1]->mPktEvents.mShiftDistance = shift;
    return count;
  }
  return -EINVAL;
}
CLASS_ATTR_RW(shift);
CLASS_ATTR_RW(itc_shift);

static int sprintPktBufInfo(char * buf, int len, ITCPacketBuffer * p)
{
  len += sprintf(&buf[len]," %u %u %u",
                 kfifo_len(&p->mFIFO),
                 !waitqueue_active(&p->mReaderQ),
                 !waitqueue_active(&p->mWriterQ));
  return len;
}


static ssize_t pru_bufs_show(struct class *c,
			     struct class_attribute *attr,
			     char *buf)
{
  int len = 0;
  int pru;
  len += sprintf(&buf[len], "pru libl libr libw pobl pobr pobw bobl bobr bobw\n");
  for (pru = 0; pru < PRU_MINORS; ++pru) {
    ITCPRUDeviceState * t = S.mPRUDeviceState[pru];
    if (!t) continue;
    len += sprintf(&buf[len], "%u", pru);
    len = sprintPktBufInfo(buf,len,&t->mLocalIB);
    len = sprintPktBufInfo(buf,len,&t->mPriorityOB);
    len = sprintPktBufInfo(buf,len,&t->mBulkOB);
    len += sprintf(&buf[len], "\n");
  }
  return len;
}
CLASS_ATTR_RO(pru_bufs);

static ssize_t pkt_bufs_show(struct class *c,
			     struct class_attribute *attr,
			     char *buf)
{
  int len = 0;
  int speed;
  len += sprintf(&buf[len], "prio uibl uibr uibw\n");
  for (speed = 0; speed < PKT_MINORS; ++speed) {
    ITCPktDeviceState * t = S.mPktDeviceState[speed];
    if (!t) continue;
    len += sprintf(&buf[len], "%u", speed);
    len = sprintPktBufInfo(buf,len,&t->mUserIB);
    len += sprintf(&buf[len], "\n");
  }
  return len;
}
CLASS_ATTR_RO(pkt_bufs);

static const char * tpStrPattern(TracePoint *tp) {
  static char buf[3+5*TRACE_MAX_LEN];
  TracePointParser atpp;
  TracePointParser * tpp = &atpp;
  tppInitForOutput(tpp,buf,sizeof(buf)/sizeof(buf[0]));
  tppGeneratePatternIfNeeded(tpp,tp);
  tppPutByte(tpp,'\0');
  return buf;
}

static bool tpMatchPacket(TracePoint *tp, const char * tag, char * pkt, int len) {
  int i;
  DBGPRINT_HEX_DUMP(DBG_TRACE_EXEC,
                    KERN_INFO, ">mtpk: ",
                    DUMP_PREFIX_NONE, 16, 1,
                    pkt, len, true);
  DBGPRINTK(DBG_TRACE_EXEC,KERN_INFO "TPEX MP (%s) Match %s %s/%d alen=%d:",
            tag,
            tpStrPattern(tp),
            strPktHdr(*pkt),
            len,
            tp->mActiveLength);

  if (tp->mActiveLength == 0 || tp->mActiveLength > len) {
    DBGPRINTK(DBG_TRACE_EXEC,KERN_CONT "fail active %d vs len %d\n",tp->mActiveLength,len);
    return false;
  }
  for (i = 0; i < tp->mActiveLength; ++i) {
    u8 byte;
    byte = pkt[i];
    if ((byte & tp->mMask[i]) != tp->mValue[i]) {
      DBGPRINTK(DBG_TRACE_EXEC,KERN_CONT "fail idx %d mask %02x value %02x byte %02x masked byte %02x\n",
                i, tp->mMask[i], tp->mValue[i], byte, (byte & tp->mMask[i]));
      return false;
    }
  }
  DBGPRINTK(DBG_TRACE_EXEC,KERN_CONT "Hit\n");
  return true;
}

static void tpReportIfMatch(TracePoint *tp, const char * tag, bool insert, char * pkt, int len, ITCPacketBuffer * ipb) {
  DBGPRINTK(DBG_TRACE_EXEC,KERN_INFO "TPEX RIMT (%s) %s %s %s/%d",
            tag,
            insert ? "Insert" : "Remove",
            tpStrPattern(tp),
            strPktHdr(*pkt),
            len);
  if (tpMatchPacket(tp,tag,pkt,len)) tpReportPkt(tag,insert,pkt,len,ipb);
 }

static void tpReportPkt(const char * tag, bool insert, char * pkt, int len, ITCPacketBuffer * ipb) {
  printk(KERN_INFO "PKTRC: (%s) %s %s/%d at %s of %s\n",
         tag,
         insert ? "Insert" : "Remove",
         strPktHdr(*pkt),
         len,
         strBuffer(ipb->mBuffer),
         strMinor(ipb->mMinor));
  DBGPRINT_HEX_DUMP(DBG_TRACE_FULL,
                    KERN_INFO, "PKTRC:",
                    DUMP_PREFIX_NONE, 16, 1,
                    pkt, len, true);
}

static int tppNextByte(TracePointParser *tpp) {
  u8 ch;
  if ((tpp->mCurrent - tpp->mProgram) >= tpp->mCount) {
    return -1;
  }
  ch = *tpp->mCurrent++;
  return (int) ch;
}

static bool tppPutByte(TracePointParser * tpp, u8 ch) {
  if ((tpp->mCurrent - tpp->mProgram) >= tpp->mCount) {
    return false;
  }
  *tpp->mCurrent++ = ch;
  return true;
}

static bool tppPutString(TracePointParser * tpp, char * str) {
  while (*str) {
    if (!tppPutByte(tpp,*str++)) return false;
  }
  return true;
}

static bool tppPutByteSpec(TracePointParser * tpp, u8 byte) {
  if (((byte&0x80) == 0) && isprint(byte)) { /* isprint sucks??  says yes to \xf0 etc?? */
    tppPutByte(tpp,'\\'); tppPutByte(tpp,byte);
  } else {
    int i;
    for (i = 4; i >= 0; i -= 4) {
      u8 h = (byte>>i)&0xf;
      if (h < 10) tppPutByte(tpp,h+'0');
      else tppPutByte(tpp,h-10+'a');
    }
  }
  return true;
}

static int tppFail(TracePointParser *tpp) {
  return -(tpp->mCurrent - tpp->mProgram + 1);
}

static bool tppUnread(TracePointParser *tpp) {
  BUG_ON(tpp->mCurrent < tpp->mProgram);
  if (tpp->mCurrent == tpp->mProgram ||  /* can't unread before the beginning*/
      (tpp->mCurrent - tpp->mProgram) >= tpp->mCount) /* and can't undo hitting eof */
    return false;
  --tpp->mCurrent;
  return true;
}

static int tppPeekByte(TracePointParser *tpp) {
  int ret = tppNextByte(tpp);
  tppUnread(tpp);
  return ret;
}

static bool tppMatch(TracePointParser *tpp, u8 byte) {
  if (tppNextByte(tpp) == byte) return true;
  tppUnread(tpp);
  return false;
}

#if 0
static void tppGet(TracePointParser *tpp, u8 byte) {
  BUG_ON(!tppMatch(tpp,byte));
}
#endif

static void tppResetTracePoint(TracePoint * tp) {
  tp->mActiveLength = 0;
}

static bool tppAddMaskTracePoint(TracePoint * tp, u8 mask) {
  DBGPRINTK(DBG_TRACE_PARSE,KERN_INFO "TPZP parse add mask %02x to len %d\n",
            mask,tp->mActiveLength);
  if (tp->mActiveLength > TRACE_MAX_LEN) return false;
  tp->mMask[tp->mActiveLength++] = mask;
  return true;
}

static bool tppAddValueTracePoint(TracePoint * tp, u8 value, int index) {
  DBGPRINTK(DBG_TRACE_PARSE,KERN_INFO "TPZP parse add value %02x to index %d/%d\n",
            value,index,tp->mActiveLength);
  if (index >= tp->mActiveLength) return false;
  tp->mValue[index] = value;
  return true;
}

static ssize_t tppParseLineComment(TracePointParser * tpp) {
  int ret;
  DBGPRINTK(DBG_TRACE_PARSE,KERN_INFO "TPZP parse comment\n");
  if (!tppMatch(tpp,'#')) return tppFail(tpp);
  while ( (ret = tppNextByte(tpp)) >= 0 && ret != '\n') { /* empty*/ }
  return 0;
}

static int tppParseByteSpec(TracePointParser *tpp) {
  int ret;

  if (tppMatch(tpp,'\\')) {
    ret = tppNextByte(tpp);
    if (ret < 0) return tppFail(tpp);
  } else {
    int i;
    int hex;
    ret = 0;
    for (i = 0; i < 2; ++i) {
      hex = tolower(tppNextByte(tpp));
      if (hex < 0) return tppFail(tpp);
      if (hex >= '0' && hex <= '9') ret = (ret<<4)|(hex-'0');
      else if (hex >='a' && hex <= 'f') ret = (ret<<4)|(hex-'a'+10);
      else return tppFail(tpp);
    }
  }

  DBGPRINTK(DBG_TRACE_PARSE,KERN_INFO "TPZP parse byte spec got %02x/%c\n", ret, ret);
  return ret;
}

static ssize_t tppParseTracePattern(TracePointParser * tpp) {
  TracePoint * tp = &tpp->mPattern;
  ssize_t ret;
  int len = 0;
  DBGPRINTK(DBG_TRACE_PARSE,KERN_INFO "TPZP parse pattern < \n");
  if (!tppMatch(tpp,'<')) return tppFail(tpp);
  tppResetTracePoint(tp);

  while (!tppMatch(tpp,'|')) {
    if ( (ret = tppParseByteSpec(tpp)) < 0) return ret;
    if (!tppAddMaskTracePoint(tp, (u8) ret)) return tppFail(tpp);
  }

  DBGPRINTK(DBG_TRACE_PARSE,KERN_INFO "TPZP parse pattern |\n");

  while (!tppMatch(tpp,'>')) {
    if (len >= tp->mActiveLength) return tppFail(tpp);
    if ( (ret = tppParseByteSpec(tpp)) < 0) return ret;
    if (!tppAddValueTracePoint(tp, (u8) ret, len)) return tppFail(tpp);
    ++len;
  }

  DBGPRINTK(DBG_TRACE_PARSE,KERN_INFO "TPZP parse pattern >\n");

  if (len != tp->mActiveLength) return tppFail(tpp);
  return 0;
}

static ssize_t tppParseMinorSet(TracePointParser * tpp) {
  int ret;
  tpp->mMinorSet = 0;
  while (1) {
    ret = tppNextByte(tpp);
    if (ret >= '0' && ret <= '3') {
      tpp->mMinorSet |= 1<<(ret-'0');
      continue;
    }
    tppUnread(tpp);
    DBGPRINTK(DBG_TRACE_PARSE,KERN_INFO "TPZP parse minor set got %x\n", tpp->mMinorSet);
    return 0;
  } 
}

static ssize_t tppParseBufferSet(TracePointParser * tpp) {
  int ret;

  tpp->mBufferSet = 0;
  while (1) {
    ret = tolower(tppNextByte(tpp));
    if      (ret == 'u') tpp->mBufferSet |= 1<<BUFFERSET_U;
    else if (ret == 'l') tpp->mBufferSet |= 1<<BUFFERSET_L;
    else if (ret == 'p') tpp->mBufferSet |= 1<<BUFFERSET_P;
    else if (ret == 'b') tpp->mBufferSet |= 1<<BUFFERSET_B;
    else {
      tppUnread(tpp);
      DBGPRINTK(DBG_TRACE_PARSE,KERN_INFO "TPZP parse buffer set got %x\n", tpp->mBufferSet);
      return 0;
    }
  }
}

static void tppStorePattern(TracePointParser * tpp, bool onInsert, bool onRemove) {
  int m, b;
  DBGPRINTK(DBG_TRACE_PARSE,KERN_INFO "TPZP store pattern enter %d %d, minor %x, buffers %x\n",
            onInsert, onRemove, tpp->mMinorSet, tpp->mBufferSet);

  /* XXX Tracing needs updating throughout for MFM minors */
  for (m = 0; m < PKT_MINOR_EVT; ++m) { /* for all PRU + PKT (but not EVT **NOR MFM**) minors */
    if (!(tpp->mMinorSet&(1<<m))) continue; /*but not this minor*/

    for (b = 0; b < 4; ++b) {  /* for all buffers */
      ITCPacketBuffer * ipb;
      if (!(tpp->mBufferSet&(1<<b))) continue; /*but not this buffer*/

      DBGPRINTK(DBG_TRACE_PARSE,KERN_INFO "TPZP store loop m%d b%d\n", m, b);

      if (m < 2) { /* pru minors */
        ITCPRUDeviceState * pru = S.mPRUDeviceState[m];
        if (!pru) continue;
        switch (b) {
        case BUFFERSET_U: continue;
        case BUFFERSET_L: ipb = &pru->mLocalIB; break;
        case BUFFERSET_P: ipb = &pru->mPriorityOB; break;
        case BUFFERSET_B: ipb = &pru->mBulkOB; break;
        default: BUG_ON(1);
        }
      } else /*if (m < 4)*/ {  /* pkt minors */
        ITCPktDeviceState * pkt = S.mPktDeviceState[m-2];
        if (!pkt) continue;
        switch (b) {
        case BUFFERSET_U: ipb = &pkt->mUserIB; break;
        case BUFFERSET_L: continue;
        case BUFFERSET_P: continue;
        case BUFFERSET_B: continue;
        default: BUG_ON(1);
        }
      } 
      if (onInsert) ipb->mTraceInsert = tpp->mPattern;
      if (onRemove) ipb->mTraceRemove = tpp->mPattern;
    }
  }
}

static ssize_t tppParseTraceProgram(TracePointParser * tpp, bool doit) {
  int ch;
  ssize_t ret;
  bool insertAct, removeAct;
  BUG_ON(!tpp);
  while ( (ch = tppPeekByte(tpp)) >= 0) {
    DBGPRINTK(DBG_TRACE_PARSE,KERN_INFO "TPZP clause got %d/%c\n",ch, (u8) ch);
    switch (tolower(ch)) {
    default:
      return tppFail(tpp);
    case ' ':
    case '\t':
    case '\n': continue; /* Ignore top-level ws */
    case '#':
      if ( (ret = tppParseLineComment(tpp)) < 0) return ret;
      break;
    case '<':
      if ( (ret = tppParseTracePattern(tpp)) < 0) return ret;
      break;
    case '0': case '1': case '2': case '3':
      if ( (ret = tppParseMinorSet(tpp)) < 0) return ret;
      break;
    case 'u': case 'l': case 'p': case 'b':
      if ( (ret = tppParseBufferSet(tpp)) < 0) return ret;
      break;
    case '+': insertAct = true;   removeAct = false;   goto act;
    case '-': insertAct = false;  removeAct = true;    goto act;
    case '*': insertAct = true;   removeAct = true;    goto act;
    case '/': insertAct = false;  removeAct = false;   goto act;

    act:
      tppNextByte(tpp); /* Consume action */
      if (doit) tppStorePattern(tpp, insertAct, removeAct);
      break;
    }
  }
  return 0;
}

static void tppResetTpp(TracePointParser * tpp) {
  tppResetTracePoint(&tpp->mPattern);
  tpp->mCount = 0;
  tpp->mProgram = 0;
  tpp->mCurrent = 0;
  tpp->mMinorSet = 0;
  tpp->mBufferSet = 0;
}

#define TPP_RESET_TRACE_PROGRAM "<|>0123ULPB*#reset\n"

static ssize_t parseTraceProgram(const char * buf, size_t count) {
  int pass;
  ssize_t ret;
  for (pass = 0; pass < 2; ++pass) {
    TracePointParser tpp;
    DBGPRINTK(DBG_TRACE_PARSE,KERN_INFO "TPZP traceprogram pass %d: '%s'(%d)\n",pass,buf,count);
    tppResetTpp(&tpp);
    if (count > 1) {
      tpp.mProgram = tpp.mCurrent = (char*) buf;
      tpp.mCount = count;
    } else if (count == 1 && buf[0] == '\n') {
      DBGPRINTK(DBG_TRACE_PARSE,KERN_INFO "TPZP defaulting to reset traceprogram\n");
      tpp.mProgram = tpp.mCurrent = TPP_RESET_TRACE_PROGRAM;
      tpp.mCount = strlen(tpp.mProgram);
    }
    ret = tppParseTraceProgram(&tpp, pass>0);
    if (ret < 0) return ret;
  }
  return count;
}

static bool tppTracePointIsEmpty(TracePoint * tp) {
  return tp->mActiveLength == 0;
}

static bool tppTracePointEqual(TracePoint * tp1, TracePoint * tp2) {
  int i;
  if (tp1->mActiveLength != tp2->mActiveLength) return false;
  for (i = 0; i < tp1->mActiveLength; ++i) {
    if (tp1->mMask[i] != tp2->mMask[i] || tp1->mValue[i] != tp2->mValue[i])
      return false;
  }
  return true;
}

static bool tppGeneratePatternIfNeeded(TracePointParser *tpp, TracePoint *tp) {
  int i;
  if (tppTracePointEqual(&tpp->mPattern,tp)) return false;
  tppPutByte(tpp,'<');
  for (i = 0; i < tp->mActiveLength; ++i) tppPutByteSpec(tpp,tp->mMask[i]);
  tppPutByte(tpp,'|');
  for (i = 0; i < tp->mActiveLength; ++i) tppPutByteSpec(tpp,tp->mValue[i]);
  tppPutByte(tpp,'>');
  tpp->mPattern = *tp;
  return true;
}

static bool tppGenerateMinorIfNeeded(TracePointParser *tpp, int m) {
  u8 minorSet = 1<<m;
  if (tpp->mMinorSet == minorSet) return false;
  tppPutByte(tpp,m+'0');
  tpp->mMinorSet = minorSet;
  return true;
}

static bool tppGenerateBufferIfNeeded(TracePointParser *tpp, int b) {
  u8 bufferSet = 1<<b;
  if (tpp->mBufferSet == bufferSet) return false;
  switch (b) {
  case BUFFERSET_U: tppPutByte(tpp,'U'); break;
  case BUFFERSET_L: tppPutByte(tpp,'L'); break;
  case BUFFERSET_P: tppPutByte(tpp,'P'); break;
  case BUFFERSET_B: tppPutByte(tpp,'B'); break;
  default: BUG_ON(1);
  }
  tpp->mBufferSet = bufferSet;
  return true;
}

static void tppGenerateActionsIfNeeded(TracePointParser *tpp, int m, int b, ITCPacketBuffer * ipb) {
  int i;
  for (i = 0; i < 2; ++i) {
    TracePoint * tp = i ? &ipb->mTraceRemove : &ipb->mTraceInsert;
    if (tppTracePointIsEmpty(tp)) continue;
    tppGeneratePatternIfNeeded(tpp,tp);
    tppGenerateMinorIfNeeded(tpp,m);
    tppGenerateBufferIfNeeded(tpp,b);
    tppPutByte(tpp,i ? '-' : '+');
  }
}

static void tppInitForOutput(TracePointParser *tpp, char *buf, u32 len) {
  tpp->mCount = len;
  tpp->mProgram = tpp->mCurrent = buf;
  tpp->mMinorSet = 0;
  tpp->mBufferSet = 0;
  tppResetTracePoint(&tpp->mPattern);
}

static void tppGenerateTraceProgram(char *buf, u32 len) {
  int m, b;
  TracePointParser atpp;
  TracePointParser * tpp = &atpp;

  tppInitForOutput(tpp,buf,len);
  tppPutString(tpp,TPP_RESET_TRACE_PROGRAM);

  for (m = 0; m < PKT_MINOR_EVT; ++m) { /* for all PRU + PKT (but not EVT) minors */
    for (b = 0; b < 4; ++b) {  /* for all buffers */
      ITCPacketBuffer * ipb;

      if (m < 2) { /* pru minors */
        ITCPRUDeviceState * pru = S.mPRUDeviceState[m];

        if (!pru) continue;
        switch (b) {
        case BUFFERSET_U: continue;
        case BUFFERSET_L: ipb = &pru->mLocalIB; break;
        case BUFFERSET_P: ipb = &pru->mPriorityOB; break;
        case BUFFERSET_B: ipb = &pru->mBulkOB; break;
        default: BUG_ON(1);
        }
      } else /* if (m < 4) */ {  /* pkt minors */
        ITCPktDeviceState * pkt = S.mPktDeviceState[m-2];
        if (!pkt) continue;
        switch (b) {
        case BUFFERSET_U: ipb = &pkt->mUserIB; break;
        case BUFFERSET_L: continue;
        case BUFFERSET_P: continue;
        case BUFFERSET_B: continue;
        default: BUG_ON(1);
        }
      } 
      tppGenerateActionsIfNeeded(tpp,m,b,ipb);
    }
  }
  tppPutByte(tpp,'\n');
}

static ssize_t trace_show(struct class *c,
			  struct class_attribute *attr,
			  char *buf)
{
  tppGenerateTraceProgram(buf,PAGE_SIZE-1);
  return strlen(buf);
}

static ssize_t trace_store(struct class *c,
			   struct class_attribute *attr,
			   const char *buf,
			   size_t count)
{
  return parseTraceProgram(buf,count);
}
CLASS_ATTR_RW(trace);

static ssize_t debug_show(struct class *c,
			  struct class_attribute *attr,
			  char *buf)
{
  sprintf(buf,"%x\n",S.mDebugFlags);
  return strlen(buf);
}

static ssize_t debug_store(struct class *c,
			   struct class_attribute *attr,
			   const char *buf,
			   size_t count)
{
  unsigned tmpdbg;
  bool add = false, sub = false;
  if (count == 0) return -EINVAL;

  if ( (*buf == '+' && (add = true)) ||
       (*buf == '-' && (sub = true)) ) ++buf;

  if (sscanf(buf,"%x",&tmpdbg) == 1) {
    if (add) S.mDebugFlags |= tmpdbg;
    else if (sub) S.mDebugFlags &= ~tmpdbg;
    else S.mDebugFlags = tmpdbg;

    printk(KERN_INFO "set debug %x\n",S.mDebugFlags);

    return count;
  }
  return -EINVAL;
}
CLASS_ATTR_RW(debug);

static ssize_t mfzid_show(struct class *c,
			  struct class_attribute *attr,
			  char *buf)
{
  MFMTileState * ts = &S.mMFMTileState;
  sprintf(buf,"%d %d %s\n",
          ts->mMFMPid,
          ts->mToken,
          ts->mMFZId
          );
  return strlen(buf);
}

static ssize_t mfzid_store(struct class *c,
			   struct class_attribute *attr,
			   const char *buf,
			   size_t count)
{
  u32 i;
  MFMTileState * ts = &S.mMFMTileState;

  if (count > MAX_MFZ_NAME_LENGTH) return -EFBIG; /*too big*/

  if (ts->mToken == 0)  /* First time randomize */
    ts->mToken = prandom_u32_max(U8_MAX)+1u; /*range 1..U8_MAX*/
  else while (++ts->mToken == 0) { /* zero-skip increment */ }

  ts->mMFMPid = task_pid_nr(current);

  for (i = 0; i < count; ++i)
    ts->mMFZId[i] = buf[i];
  ts->mMFZId[i] = '\0';
  
  /* Invalidate the KITCs */
  for (i = 0; i < MFM_MINORS; ++i) {
    BUG_ON(!S.mMFMDeviceState[i]);
    S.mMFMDeviceState[i]->mStale = true;
  }

  printk(KERN_INFO "mfzid set; len=%d, token=%d, written by %d\n",
         count,
         ts->mToken,
         ts->mMFMPid);
  return count;
}
CLASS_ATTR_RW(mfzid);


static ssize_t itc_pin_write_handler(unsigned pru, unsigned prudir, unsigned bit,
                                     struct class *c,
                                     struct class_attribute *attr,
                                     const char *buf,
                                     size_t count)
{
  char msg[RPMSG_MAX_PACKET_SIZE];
  int ret;
  unsigned val;
  if (sscanf(buf,"%u",&val) != 1)
    return -EINVAL;
  if (val > 1)
    return -EINVAL;

  /* We wait for a return just to get it out of the buffer*/
  ret = sendMsgToPRU(pru, 1, msg, RPMSG_MAX_PACKET_SIZE, "B%c%c-", bit, val);
  if (ret < 0) return ret;

  return count;
}

static uint32_t extract32(const char *p) {
  int i;
  uint32_t ret = 0;

  for (i = 0; i < 4; ++i)
    ret |= ((unsigned) p[i])<<(i<<3);
  return ret;
}

static ssize_t itc_pin_read_handler(unsigned pru, unsigned prudir, unsigned bit,
                                    struct class *c,
                                    struct class_attribute *attr,
                                    char *buf)
{
  char msg[RPMSG_MAX_PACKET_SIZE];
  int ret;

  ret = sendMsgToPRU(pru, 1, msg, RPMSG_MAX_PACKET_SIZE, "Rxxxx-");
  if (ret < 0) return ret;

  if (msg[0]!='R' || msg[5] != '-') {
    printk(KERN_WARNING "Expected 'Rxxxx-' packet got '%s'(pru=%u,prudir=%u,bit=%u)\n",
           msg, pru, prudir, bit);
    return -EIO;
  }

  {
    uint32_t r31 = extract32(&msg[1]);
    uint32_t val = (r31>>bit)&1;
    //    printk(KERN_INFO "R31 0x%08x@%u = %u\n", r31, bit, val);
    return sprintf(buf,"%u\n", val);
  }
}

#define ITC_INPUT_PIN_FUNC(dir,pin)                                     \
static ssize_t dir##_##pin##_show(struct class *c,			\
				    struct class_attribute *attr,	\
				    char *buf)				\
{                                                                       \
  return itc_pin_read_handler(DIR_NAME_TO_PRU(dir),                     \
                              DIR_NAME_TO_PRUDIR(dir),                  \
                              DIR_NAME_AND_PIN_TO_R31_BIT(dir,pin),     \
                              c,attr,buf);                              \
}                                                                       \
CLASS_ATTR_RO(dir##_##pin);						\

#define ITC_OUTPUT_PIN_FUNC(dir,pin)                                    \
static ssize_t dir##_##pin##_store(struct class *c,			\
				   struct class_attribute *attr,	\
				   const char *buf,			\
				   size_t count)			\
{                                                                       \
  return itc_pin_write_handler(DIR_NAME_TO_PRU(dir),                    \
                               DIR_NAME_TO_PRUDIR(dir),                 \
                               DIR_NAME_AND_PIN_TO_R30_BIT(dir,pin),    \
                               c,attr,buf,count);                       \
}                                                                       \
CLASS_ATTR_WO(dir##_##pin);						\


/* ******
   GENERATE DISPATCH FUNCTIONS */
#define XX(dir) \
  ITC_OUTPUT_PIN_FUNC(dir,TXRDY) \
  ITC_OUTPUT_PIN_FUNC(dir,TXDAT) \
  ITC_INPUT_PIN_FUNC(dir,RXRDY) \
  ITC_INPUT_PIN_FUNC(dir,RXDAT) \

FOR_XX_IN_ITC_ALL_DIR

#undef XX
/* GENERATE DISPATCH FUNCTIONS: DONE*/

/* ******
   GENERATE SYSFS CLASS ATTRIBUTES FOR ITC PINS */
/* input pins are read-only */
#define ITC_INPUT_PIN_ATTR(dir,pin) \
  &class_attr_##dir##_##pin.attr
/* output pins are read-write */
#define ITC_OUTPUT_PIN_ATTR(dir,pin) \
  &class_attr_##dir##_##pin.attr
#define XX(dir) \
  ITC_OUTPUT_PIN_ATTR(dir,TXRDY), \
  ITC_OUTPUT_PIN_ATTR(dir,TXDAT), \
  ITC_INPUT_PIN_ATTR(dir,RXRDY), \
  ITC_INPUT_PIN_ATTR(dir,RXDAT), \

static struct attribute * class_itc_pkt_attrs[] = {
  FOR_XX_IN_ITC_ALL_DIR
  &class_attr_poke.attr,
  &class_attr_status.attr,
  &class_attr_statistics.attr,
  &class_attr_trace_start_time.attr,
  &class_attr_itc_trace_start_time.attr,
  &class_attr_shift.attr,
  &class_attr_itc_shift.attr,
  &class_attr_pru_bufs.attr,
  &class_attr_pkt_bufs.attr,
  &class_attr_trace.attr,
  &class_attr_debug.attr,
  NULL,
};
ATTRIBUTE_GROUPS(class_itc_pkt);

#undef XX
/* GENERATE SYSFS CLASS ATTRIBUTES FOR ITC PINS: DONE */


static int itc_pkt_open(struct inode *inode, struct file *filp)
{
  int ret = -EBUSY;
  /* All our device state structs begin with an ITCCharDeviceState! */
  ITCCharDeviceState * cdevstate = (ITCCharDeviceState *) inode->i_cdev;

#if MORE_DEBUGGING
  printk(KERN_INFO "itc_pkt_open %d:%d\n",
         MAJOR(cdevstate->mDevt),
         MINOR(cdevstate->cDevt));
#endif

  if (!cdevstate->mDeviceOpenedFlag) {
    cdevstate->mDeviceOpenedFlag = true;
    filp->private_data = cdevstate;
    ret = 0;
  }

  if (ret)
    dev_err(cdevstate->mLinuxDev, "Device already open\n");

  return ret;
}

static int itc_pktevt_open(struct inode *inode, struct file *filp)
{
  int ret = -EBUSY;
  /* All our device state structs begin with an ITCCharDeviceState! */
  ITCCharDeviceState * cdevstate = (ITCCharDeviceState *) inode->i_cdev;

#if MORE_DEBUGGING
  printk(KERN_INFO "itc_pktevt_open %d:%d\n",
         MAJOR(cdevstate->mDevt),
         MINOR(cdevstate->cDevt));
#endif

  if (!cdevstate->mDeviceOpenedFlag) {
    cdevstate->mDeviceOpenedFlag = true;
    filp->private_data = cdevstate;
    ret = 0;
  }

  if (ret)
    dev_err(cdevstate->mLinuxDev, "Device already open\n");

  return ret;
}

static int itc_itcevt_open(struct inode *inode, struct file *filp)
{
  int ret = -EBUSY;
  /* All our device state structs begin with an ITCCharDeviceState! */
  ITCCharDeviceState * cdevstate = (ITCCharDeviceState *) inode->i_cdev;

#if MORE_DEBUGGING
  printk(KERN_INFO "itc_itcevt_open %d:%d\n",
         MAJOR(cdevstate->mDevt),
         MINOR(cdevstate->cDevt));
#endif

  if (!cdevstate->mDeviceOpenedFlag) {
    cdevstate->mDeviceOpenedFlag = true;
    filp->private_data = cdevstate;
    ret = 0;
  }

  if (ret)
    dev_err(cdevstate->mLinuxDev, "Device already open\n");

  return ret;
}

static int itc_mfmitc_open(struct inode *inode, struct file *filp)
{

  ITCMFMDeviceState * mfmdevstate = (ITCMFMDeviceState *) inode->i_cdev;

  /* ITCMFMDeviceState structs begin with an ITCPktDeviceState! */
  ITCPktDeviceState * pktdevstate = (ITCPktDeviceState *) mfmdevstate;

  /* Which in turn begin with an ITCPktDeviceState! */
  ITCCharDeviceState * cdevstate = (ITCCharDeviceState *) pktdevstate;

#if MORE_DEBUGGING
  printk(KERN_INFO "itc_mfmitc_open %d:%d\n",
         MAJOR(cdevstate->mDevt),
         MINOR(cdevstate->cDevt));
#endif

  if (cdevstate->mDeviceOpenedFlag) return -EBUSY;  /* Already in use */
  if (mfmdevstate->mStale) return -ESTALE;          /* mfzid was written, we need to be closed */

  cdevstate->mDeviceOpenedFlag = true;
  filp->private_data = mfmdevstate;

  return 0;
}


/** @brief The callback for when the device is closed/released by
 *  the userspace program
 *  @param inodep A pointer to an inode object (defined in linux/fs.h)
 *  @param filep A pointer to a file object (defined in linux/fs.h)
 */
static int itc_pkt_release(struct inode *inode, struct file *filp)
{
  /* All our device state structs begin with an ITCCharDeviceState! */
  ITCCharDeviceState * cdevstate = (ITCCharDeviceState *) inode->i_cdev;

#if MORE_DEBUGGING
  printk(KERN_INFO "itc_pkt_release %d:%d\n",
         MAJOR(cdevstate->mDevt),
         MINOR(cdevstate->mDevt));
#endif

  cdevstate->mDeviceOpenedFlag = false;

  return 0;
}

static int itc_pktevt_release(struct inode *inode, struct file *filp)
{
  /* All our device state structs begin with an ITCCharDeviceState! */
  ITCCharDeviceState * cdevstate = (ITCCharDeviceState *) inode->i_cdev;

#if MORE_DEBUGGING
  printk(KERN_INFO "itc_pktevt_release %d:%d\n",
         MAJOR(cdevstate->mDevt),
         MINOR(cdevstate->mDevt));
#endif

  cdevstate->mDeviceOpenedFlag = false;

  return 0;
}

static int itc_itcevt_release(struct inode *inode, struct file *filp)
{
  /* All our device state structs begin with an ITCCharDeviceState! */
  ITCCharDeviceState * cdevstate = (ITCCharDeviceState *) inode->i_cdev;

#if MORE_DEBUGGING
  printk(KERN_INFO "itc_itcevt_release %d:%d\n",
         MAJOR(cdevstate->mDevt),
         MINOR(cdevstate->mDevt));
#endif

  cdevstate->mDeviceOpenedFlag = false;

  return 0;
}

static int itc_mfmitc_release(struct inode *inode, struct file *filp)
{

  ITCMFMDeviceState * mfmdevstate = (ITCMFMDeviceState *) inode->i_cdev;

  /* ITCMFMDeviceState structs begin with an ITCPktDeviceState! */
  ITCPktDeviceState * pktdevstate = (ITCPktDeviceState *) mfmdevstate;

  /* Which in turn begin with an ITCPktDeviceState! */
  ITCCharDeviceState * cdevstate = (ITCCharDeviceState *) pktdevstate;

#if MORE_DEBUGGING
  printk(KERN_INFO "itc_mfmitc_release %d:%d\n",
         MAJOR(cdevstate->mDevt),
         MINOR(cdevstate->cDevt));
#endif

  cdevstate->mDeviceOpenedFlag = false; /* OK, we're not open */
  mfmdevstate->mStale = false;          /* OK, we're not stale if reopened now */

  return 0;
}


const char * getDir8Name(u8 dir8) {
  switch (dir8) {
  case DIR_NAME_TO_DIR8(NT): return "N?";  /* what what? */
  case DIR_NAME_TO_DIR8(NE): return "NE";
  case DIR_NAME_TO_DIR8(ET): return "ET";
  case DIR_NAME_TO_DIR8(SE): return "SE";
  case DIR_NAME_TO_DIR8(ST): return "S?";  /* on T2 you say? */
  case DIR_NAME_TO_DIR8(SW): return "SW";
  case DIR_NAME_TO_DIR8(WT): return "WT";
  case DIR_NAME_TO_DIR8(NW): return "NW";
  }
  return "??";
}

static void setITCEnabledStatus(int pru, int prudir, int enabled) {
  u32 dir8 = mapPruAndPrudirToDir8(pru,prudir); /*returns 8 on bad*/
  u32 dir8x4 = dir8<<2;
  int bit = (0x1<<dir8x4);
  bool existing = (S.mItcEnabledStatus & bit);
  if (enabled && !existing) {
    S.mItcEnabledStatus |= bit;
    printk(KERN_INFO "ITCCHANGE:UP:%s\n",
           getDir8Name(mapPruAndPrudirToDir8(pru,prudir)));
    ADD_ITC_EVENT(makeItcDirEvent(mapDir8ToDir6(dir8),IEV_DIR_ITCUP));
  } else if (!enabled && existing) {
    S.mItcEnabledStatus &= ~bit;
    printk(KERN_INFO "ITCCHANGE:DOWN:%s\n",
           getDir8Name(mapPruAndPrudirToDir8(pru,prudir)));
    ADD_ITC_EVENT(makeItcDirEvent(mapDir8ToDir6(dir8),IEV_DIR_ITCDN));
  }
}

bool isITCEnabledStatusByDir8(int dir8) {
  int dir8x4 = dir8<<2;
  return (S.mItcEnabledStatus>>dir8x4)&0x1;
}

static int routeOutboundStandardPacket(const unsigned char pktHdr, size_t pktLen)
{
  int dir8;
  int newminor;
  if (pktLen == 0) return -EINVAL;
  if ((pktHdr & 0x80) == 0) return -ENXIO; /* only standard packets can be routed */
  dir8 = pktHdr & 0x7;
  if (!isITCEnabledStatusByDir8(dir8)) return -EHOSTUNREACH;

  switch (dir8) {

  default: newminor = -ENODEV; break;
#define XX(dir) case DIR_NAME_TO_DIR8(dir): newminor = DIR_NAME_TO_PRU(dir); break;
FOR_XX_IN_ITC_ALL_DIR
#undef XX
  }

  return newminor;
}

ssize_t trySendUrgentRoutedKernelPacket(const u8 *pkt, size_t count)
{
  int minor;
  ITCCharDeviceState * cdevstate;
  ITCPRUDeviceState * prudevstate;
  ITCPacketBuffer * ipb;
  int ret;
        
  if (count == 0 || count > ITC_MAX_PACKET_SIZE) return -EINVAL;

  minor = routeOutboundStandardPacket(*pkt, count);
  if (minor < 0) return minor; /* bad routing */

  BUG_ON(minor > PRU_MINOR_PRU1);

  cdevstate = (ITCCharDeviceState*) S.mPRUDeviceState[minor];
  BUG_ON(!cdevstate);

  prudevstate = (ITCPRUDeviceState*) cdevstate;
  ipb = &prudevstate->mPriorityOB;  /*priority dispatch only at present*/

  DBGPRINTK(DBG_PKT_ROUTE,
            KERN_INFO "Routing %s %s/%d packet to %s\n",
            "priority",
            strPktHdr(*pkt),
            count,
            cdevstate->mName);

  if (kfifo_avail(&ipb->mFIFO) < count) return -EAGAIN; /* Never block */
  ret = kfifo_in(&ipb->mFIFO, pkt, count); /*0 on no room else count*/

  wakeOBPktShipper(); /* if we got this far, kick the linux->pru thread */

  return ret ? ret : -ENOSPC;
}

static ssize_t writePacketHelper(struct file *file,
                                 const char __user *buf,
                                 size_t count, loff_t *offset,
                                 ITCCharDeviceState * cdevstate)
{
  int minor = MINOR(cdevstate->mDevt);

  unsigned char pktHdr;
  bool bulkRate = true;  /* assume slow boat */

  DBGPRINTK(DBG_PKT_SENT, KERN_INFO "writePacketHelper(%d) enter %s\n",minor, cdevstate->mName);

  if (count > RPMSG_MAX_PACKET_SIZE) {
    dev_err(cdevstate->mLinuxDev, "Data length (%d) exceeds rpmsg buffer size", count);
    return -EINVAL;
  }

  if (copy_from_user(&pktHdr, buf, 1)) { /* peek at first byte */
    dev_err(cdevstate->mLinuxDev, "Failed to copy data");
    return -EFAULT;
  }

  DBGPRINTK(DBG_PKT_SENT, KERN_INFO "writePacketHelper(%d) read pkt type %s from user\n",minor, strPktHdr(pktHdr));

  if (minor == PKT_MINOR_BULK || minor == PKT_MINOR_FLASH ||
      (minor >= PKT_MINOR_MFM_ET && minor <= PKT_MINOR_MFM_NE)) {
    int newMinor = routeOutboundStandardPacket(pktHdr, count);

    DBGPRINTK(DBG_PKT_SENT, KERN_INFO "writePacketHelper(%d) routing %s to minor %d\n",minor, strPktHdr(pktHdr), newMinor);

    //    printk(KERN_INFO "CONSIDERINGO ROUTINGO\n");
    if (newMinor < 0)
      return newMinor;          // bad routing

    if (count > ITC_MAX_PACKET_SIZE) {
      dev_err(cdevstate->mLinuxDev, "Routable packet size (%d) exceeds ITC length max (255)", count);
      return -EINVAL;
    }

    if (minor != PKT_MINOR_BULK) bulkRate = false; 

    BUG_ON(newMinor > PRU_MINOR_PRU1);

    cdevstate = (ITCCharDeviceState*) S.mPRUDeviceState[newMinor];
    DBGPRINTK(DBG_PKT_ROUTE,
              KERN_INFO "Routing %s %s/%d packet to %s\n",
              bulkRate ? "bulk" : "priority",
              strPktHdr(pktHdr),
              count,
              cdevstate->mName);
    BUG_ON(!cdevstate);
  }

  {
    int ret = 0;
    ITCPRUDeviceState * prudevstate = (ITCPRUDeviceState*) cdevstate;
    ITCPacketBuffer * ipb = bulkRate ? &prudevstate->mBulkOB : &prudevstate->mPriorityOB;
    unsigned int copied;

    DBGPRINTK(DBG_PKT_SENT, KERN_INFO "writePacketHelper(%d) prewait %s\n",minor, ipb->mName);
    while (kfifo_avail(&ipb->mFIFO) < count) {
      if (file->f_flags & O_NONBLOCK) {
        ret = -EAGAIN;
        break;
      }
      if (wait_event_interruptible(ipb->mWriterQ, !(kfifo_avail(&ipb->mFIFO) < count))) {
        ret = -ERESTARTSYS;
        break;
      }
      DBGPRINTK(DBG_PKT_ROUTE,
                KERN_INFO "Waiting for %d space, %d available\n",
                count, kfifo_avail(&ipb->mFIFO));
    }

    if (ret == 0) {
      char tmp[TRACE_MAX_LEN + 1]; /* room for null */
      {
        /* copy enough to evaluate tp */
        TracePoint * tp = &ipb->mTraceInsert;
        int len = tp->mActiveLength || 1; /* copy at least one, for ADD_PKT_EVENT below */
        int uncopied = copy_from_user(tmp,buf,len);
        tmp[len] = 0;
        DBGPRINTK(DBG_TRACE_EXEC,KERN_INFO "TPEX UWRITE (%s) '%s'/%d",
                  cdevstate->mName,
                  tmp,
                  len);
        if (uncopied == 0 && tpMatchPacket(tp,cdevstate->mName,tmp,len)) {
          /* copy whole thing to report */
          static char tmpbuf[ITC_MAX_PACKET_SIZE];
          if (copy_from_user(tmpbuf, buf, count)) {
            dev_err(cdevstate->mLinuxDev, "Failed to copy data");
            return -EFAULT;
          }
          tpReportPkt(prudevstate->mCDevState.mName, true, tmpbuf, len, ipb);
        }
      }
      ret = kfifo_from_user(&ipb->mFIFO, buf, count, &copied);

      if (ret == 0) 
        ADD_PKT_EVENT(makePktXfrEvent(PEV_XFR_FROM_USR, minor != PKT_MINOR_BULK, log2in3(copied), tmp[0]&0x7));

      DBGPRINTK(DBG_PKT_ROUTE,
                KERN_INFO "Copied %d user->%s:%s, count %d, avail %d, len %d, ret %d\n",
                copied,
                prudevstate->mCDevState.mName,
                ipb->mName,
                count,
                kfifo_avail(&ipb->mFIFO),
                kfifo_len(&ipb->mFIFO),
                ret);
      if (ret == 0) wakeOBPktShipper(); /* kick the linux->pru thread */
    }

    return ret ? ret : copied;
  }
}

/** @brief This callback used when data is being written to the device
 *  from user space.  Note that although rpmsg allows messages over
 *  500 bytes long, so that's the limit for talking to a local PRU,
 *  intertile packets are limited to at most 255 bytes.  Here, that
 *  limit is enforced only for minor 2 (/dev/itc/bulk) and minor 3
 *  (/dev/itc/flash) because packets sent there are necessarily
 *  routable intertile.
 *
 *  @param filp A pointer to a file object
 *  @param buf The buffer to that contains the data to write to the device
 *  @param count The number of bytes to write from buf
 *  @param offset The offset if required
 */

static ssize_t itc_pkt_write(struct file *file,
                             const char __user *buf,
                             size_t count, loff_t *offset)
{
  /* All our device state structs begin with an ITCCharDeviceState! */
  ITCCharDeviceState * cdevstate = (ITCCharDeviceState *) file->private_data;
  
  return writePacketHelper(file,buf,count,offset,cdevstate);
}

static ssize_t itc_pktevt_write(struct file *filep, const char *buffer, size_t len, loff_t *offset)
{
  /* All our device state structs begin with an ITCCharDeviceState! */
  ITCCharDeviceState * cdevstate = (ITCCharDeviceState *) filep->private_data;
  int minor = MINOR(cdevstate->mDevt);
  ITCEvtDeviceState * evtdevstate = (ITCEvtDeviceState*) cdevstate;

  s32 ret;
  u8 evtCmd;

  BUG_ON(minor != PKT_MINOR_EVT);

  if (len != 1)  /* Only allowed to write one byte */
    return -EPERM;

  ret = copy_from_user(&evtCmd, buffer, 1);
  if (ret != 0) {
    printk(KERN_INFO "Itc: copy_from_user failed\n");
    return -EFAULT;
  }

  if (evtCmd != 0)       /*we only support 0->RESET at the moment*/
    return -EINVAL;

  // Flush the event kfifo and set up for trace
  while ( (ret = startPktEventTrace(&evtdevstate->mPktEvents)) ) {
    if ((filep->f_flags & O_NONBLOCK) || (ret != -EINTR))
      break;
  }

  return ret ? ret : len;
}

static ssize_t itc_itcevt_write(struct file *filep, const char *buffer, size_t len, loff_t *offset)
{
  /* All our device state structs begin with an ITCCharDeviceState! */
  ITCCharDeviceState * cdevstate = (ITCCharDeviceState *) filep->private_data;
  int minor = MINOR(cdevstate->mDevt);
  ITCEvtDeviceState * evtdevstate = (ITCEvtDeviceState*) cdevstate;

  s32 ret;
  u8 evtCmd;

  BUG_ON(minor != PKT_MINOR_ITC_EVT);

  if (len != 1)  /* Only allowed to write one byte */
    return -EPERM;

  ret = copy_from_user(&evtCmd, buffer, 1);
  if (ret != 0) {
    printk(KERN_INFO "Itc: copy_from_user failed\n");
    return -EFAULT;
  }

  if (evtCmd != 0)       /*we only support 0->RESET at the moment*/
    return -EINVAL;

  // Flush the event kfifo and set up for trace
  while ( (ret = startPktEventTrace(&evtdevstate->mPktEvents)) ) {
    if ((filep->f_flags & O_NONBLOCK) || (ret != -EINTR))
      break;
  }

  return ret ? ret : len;
}

static ssize_t itc_pkt_read(struct file *file, char __user *buf,
                            size_t count, loff_t *ppos)
{
  int ret = 0;
  unsigned int copied;

  ITCCharDeviceState *cdevstate = file->private_data;
  int minor = MINOR(cdevstate->mDevt);

  ITCPacketBuffer * ipb;
  ITCPacketFIFO * fifo;

  DBGPRINTK(DBG_PKT_RCVD, KERN_INFO "itc_pkt_read(%d) enter %s\n",minor, cdevstate->mName);

  switch (minor) {  /* Find the relevant ipb */
  case 0: case 1:     /* PRU local */
    ipb = &(((ITCPRUDeviceState *) cdevstate)->mLocalIB);
    break;
  case 2: case 3:     /* Routed packets */
    ipb = &(((ITCPktDeviceState *) cdevstate)->mUserIB);
    break;
  default: BUG_ON(1);
  }

  fifo = &(ipb->mFIFO);

  DBGPRINTK(DBG_PKT_RCVD, KERN_INFO "itc_pkt_read(%d) prelock ipb %s\n",minor,ipb->mName);

  if (mutex_lock_interruptible(&ipb->mLock))
    return -ERESTARTSYS;

  DBGPRINTK(DBG_PKT_RCVD, KERN_INFO "itc_pkt_read(%d) pre kfifo check, %s empty=%d, len=%d, pktlen=%d\n",
            minor,
            ipb->mName,
            kfifo_is_empty(fifo),
            kfifo_len(fifo),
            kfifo_len(fifo) == 0 ? -1 : kfifo_peek_len(fifo));

  while (kfifo_is_empty(fifo)) {
    if (file->f_flags & O_NONBLOCK) {
      ret = -EAGAIN;
      break;
    }
    if (wait_event_interruptible(ipb->mReaderQ, !kfifo_is_empty(fifo))) {
      ret = -ERESTARTSYS;
      break;
    }
  }

  DBGPRINTK(DBG_PKT_RCVD, KERN_INFO "itc_pkt_read(%d) post kfifo check ret= %d\n",minor,ret);

  if (ret == 0) {
    char tmp[TRACE_MAX_LEN+1];
    TracePoint * tp = &ipb->mTraceRemove;
    int len = tp->mActiveLength || 1; /* Read at least 1 for ADD_PKT_EVENT below*/
    /* just peek at enough to evaluate the trace point */
    if (len == kfifo_out_peek(fifo, tmp, len)) {
      tmp[len] = 0; /*paranoia*/
      if (tpMatchPacket(tp,cdevstate->mName,tmp,len)) {
        /* and only for for the whole thing when we hit */
        static char tmpbuf[ITC_MAX_PACKET_SIZE];
        len = kfifo_out_peek(fifo, tmpbuf, ITC_MAX_PACKET_SIZE);
        tpReportPkt(cdevstate->mName, false, tmpbuf, len, ipb);
      }
    }
    ret = kfifo_to_user(fifo, buf, count, &copied);
    if (ret == 0)
      ADD_PKT_EVENT(makePktXfrEvent(PEV_XFR_TO_USR,minor != PKT_MINOR_BULK, log2in3(copied), tmp[0]&0x7));
    DBGPRINTK(DBG_PKT_RCVD, KERN_INFO "itc_pkt_read(%d) post kfifo_to_user ret=%d copied=%d\n",
              minor,ret,copied);
  }
  mutex_unlock(&ipb->mLock);

  return ret ? ret : copied;
}

static ssize_t itc_pktevt_read(struct file *file, char __user *buf,
                               size_t len, loff_t *ppos)
{
  int ret = 0;
  u32 copied;
  ITCCharDeviceState *cdevstate = file->private_data;
  int minor = MINOR(cdevstate->mDevt);
  ITCPktEventState * pes = &(((ITCEvtDeviceState *) cdevstate)->mPktEvents);
  ITCPktEventFIFO * fifo = &(pes->mEvents);

  BUG_ON(minor != PKT_MINOR_EVT);
  len = len/sizeof(ITCPktEvent)*sizeof(ITCPktEvent); // Round off

  DBGPRINTK(DBG_PKT_RCVD, KERN_INFO "itc_pktevt_read(%s) enter\n",cdevstate->mName);

  // Get read lock to read the event kfifo
  while ( (ret = mutex_lock_interruptible(&pes->mPktEventReadMutex)) ) {
    if ((file->f_flags & O_NONBLOCK) || (ret != -EINTR)) return ret;
  }

  DBGPRINTK(DBG_PKT_RCVD, KERN_INFO "itc_pktevt_read(%s) pre kfifo check, empty=%d, len=%d, pktlen=%d\n",
            cdevstate->mName,
            kfifo_is_empty(fifo),
            kfifo_len(fifo),
            kfifo_len(fifo) == 0 ? -1 : kfifo_peek_len(fifo));

  ret = kfifo_to_user(fifo, buf, len, &copied);
  mutex_unlock(&pes->mPktEventReadMutex);

  return ret ? ret : copied;
}

static ssize_t itc_itcevt_read(struct file *file, char __user *buf,
                               size_t len, loff_t *ppos)
{
  int ret = 0;
  u32 copied;
  ITCCharDeviceState *cdevstate = file->private_data;
  int minor = MINOR(cdevstate->mDevt);
  ITCPktEventState * pes = &(((ITCEvtDeviceState *) cdevstate)->mPktEvents);
  ITCPktEventFIFO * fifo = &(pes->mEvents);

  BUG_ON(minor != PKT_MINOR_ITC_EVT);
  len = len/sizeof(ITCPktEvent)*sizeof(ITCPktEvent); // Round off

  DBGPRINTK(DBG_PKT_RCVD, KERN_INFO "itc_pktevt_read(%s) enter\n",cdevstate->mName);

  // Get read lock to read the event kfifo
  while ( (ret = mutex_lock_interruptible(&pes->mPktEventReadMutex)) ) {
    if ((file->f_flags & O_NONBLOCK) || (ret != -EINTR)) return ret;
  }

  DBGPRINTK(DBG_PKT_RCVD, KERN_INFO "itc_itcevt_read(%s) pre kfifo check, empty=%d, len=%d, pktlen=%d\n",
            cdevstate->mName,
            kfifo_is_empty(fifo),
            kfifo_len(fifo),
            kfifo_len(fifo) == 0 ? -1 : kfifo_peek_len(fifo));

  ret = kfifo_to_user(fifo, buf, len, &copied);
  mutex_unlock(&pes->mPktEventReadMutex);

  return ret ? ret : copied;
}

static ssize_t itc_mfmitc_read(struct file *file, char __user *buf,
                               size_t count, loff_t *ppos)
{
  ITCMFMDeviceState * mfmdevstate = (ITCMFMDeviceState *) file->private_data;

  /* ITCMFMDeviceState structs begin with an ITCPktDeviceState! */
  ITCPktDeviceState * pktdevstate = (ITCPktDeviceState *) mfmdevstate;

  /* Which in turn begin with an ITCPktDeviceState! */
  ITCCharDeviceState * cdevstate = (ITCCharDeviceState *) pktdevstate;

  ITCPacketBuffer * ipb;
  ITCPacketFIFO * fifo;

  int ret = 0;
  u32 copied;

  int minor = MINOR(cdevstate->mDevt);
  DBGPRINTK(DBG_PKT_RCVD, KERN_INFO "itc_mfmitc_read(%d) enter %s\n",minor, cdevstate->mName);

  BUG_ON(minor < PKT_MINOR_MFM_ET || minor > PKT_MINOR_MFM_NE);

  ipb = &(pktdevstate->mUserIB);
  fifo = &(ipb->mFIFO);

  DBGPRINTK(DBG_PKT_RCVD, KERN_INFO "itc_mfmitc_read(%d) prelock ipb %s\n",minor,ipb->mName);

  if (mutex_lock_interruptible(&ipb->mLock))
    return -ERESTARTSYS;

  DBGPRINTK(DBG_PKT_RCVD, KERN_INFO "itc_mfmitc_read(%d) pre kfifo check, %s empty=%d, len=%d, pktlen=%d\n",
            minor,
            ipb->mName,
            kfifo_is_empty(fifo),
            kfifo_len(fifo),
            kfifo_len(fifo) == 0 ? -1 : kfifo_peek_len(fifo));

  while (kfifo_is_empty(fifo)) {
    if (file->f_flags & O_NONBLOCK) {
      ret = -EAGAIN;
      break;
    }
    if (wait_event_interruptible(ipb->mReaderQ, !kfifo_is_empty(fifo))) {
      ret = -ERESTARTSYS;
      break;
    }
  }

  DBGPRINTK(DBG_PKT_RCVD, KERN_INFO "itc_mfmitc_read(%d) post kfifo check ret= %d\n",minor,ret);

  if (ret == 0) {
    ret = kfifo_to_user(fifo, buf, count, &copied);
    DBGPRINTK(DBG_PKT_RCVD, KERN_INFO "itc_mfmitc_read(%d) post kfifo_to_user ret=%d copied=%d\n",
              minor,ret,copied);
  }
  mutex_unlock(&ipb->mLock);

  return ret ? ret : copied;
}

static ssize_t itc_mfmitc_write(struct file *file,
                                const char __user *buf,
                                size_t count, loff_t *offset)
{
  ITCMFMDeviceState * mfmdevstate = (ITCMFMDeviceState *) file->private_data;

  /* ITCMFMDeviceState structs begin with an ITCPktDeviceState! */
  ITCPktDeviceState * pktdevstate = (ITCPktDeviceState *) mfmdevstate;

  /* Which in turn begin with an ITCPktDeviceState! */
  ITCCharDeviceState * cdevstate = (ITCCharDeviceState *) pktdevstate;

  return writePacketHelper(file,buf,count,offset,cdevstate);
}


static const struct file_operations itc_pkt_fops = {
  .owner= THIS_MODULE,
  .open	= itc_pkt_open,
  .read = itc_pkt_read,
  .write= itc_pkt_write,
  .release= itc_pkt_release,
};

static const struct file_operations itc_pktevt_fops = {
  .owner= THIS_MODULE,
  .open	= itc_pktevt_open,
  .read = itc_pktevt_read,
  .write= itc_pktevt_write,
  .release= itc_pktevt_release,
};

static const struct file_operations itc_itcevt_fops = {
  .owner= THIS_MODULE,
  .open	= itc_itcevt_open,
  .read = itc_itcevt_read,
  .write= itc_itcevt_write,
  .release= itc_itcevt_release,
};

static const struct file_operations itc_mfmitc_fops = {
  .owner= THIS_MODULE,
  .open	= itc_mfmitc_open,
  .read = itc_mfmitc_read,
  .write= itc_mfmitc_write,
  .release= itc_mfmitc_release,
};


static const struct file_operations *(itc_pkt_fops_ptrs[MINOR_DEVICES]) = {
  &itc_pkt_fops,       /* PRU_MINOR_PRU0 */
  &itc_pkt_fops,       /* PRU_MINOR_PRU1 */
  &itc_pkt_fops,       /* PRU_MINOR_ITC */
  &itc_pkt_fops,       /* PRU_MINOR_MFM */
  &itc_pktevt_fops,    /* PRU_MINOR_EVT */
  &itc_itcevt_fops,    /* PRU_MINOR_ITC_EVT */
  &itc_mfmitc_fops,    /* PKT_MINOR_MFM_ET */
  &itc_mfmitc_fops,    /* PKT_MINOR_MFM_SE */
  &itc_mfmitc_fops,    /* PKT_MINOR_MFM_SW */
  &itc_mfmitc_fops,    /* PKT_MINOR_MFM_WT */
  &itc_mfmitc_fops,    /* PKT_MINOR_MFM_NW */
  &itc_mfmitc_fops     /* PKT_MINOR_MFM_NE */
};

// See firmware/LinuxIO.c:CSendFromThread for 0xc3 packet format
static void handleLocalStandard3(int minor, u8* bytes, int len)
{
  u8 code, pru, prudir, val4;
  const char * dirname;
  ITCTrafficStats * t;
  if (len < 6 || bytes[5] != ':') {
    printk(KERN_ERR "Malformed locstd3 (len=%d)\n",len);
    return;
  }

  code = bytes[1];
  pru = bytes[2]-'0';
  prudir = bytes[3]-'0';
  val4 = bytes[4]-'0';

  dirname = getDir8Name(mapPruAndPrudirToDir8(pru,prudir));

  t = getITCTrafficStats(pru,prudir);  /* t == 0 if prudir == 3 */

  switch (code) {
  default:
    printk(KERN_INFO "(%s) Unhandled locstd3 '%c' (pru=%d, prudir=%d, val4 =%x)\n",dirname,code,pru,prudir,val4);
    break;

  case 'P': // Announcing packet sync on pru,prudir
    DBGPRINTK(DBG_PKT_ROUTE, KERN_INFO "%s: Packet sync\n",dirname);
    setITCEnabledStatus(pru,prudir,1);
    BUG_ON(!t);
    ++t->mPacketSyncAnnouncements;
    break;

  case 'F': // Announcing sync failure on pru,prudir
    DBGPRINTK(DBG_PKT_ROUTE, KERN_INFO "%s: Frame error (val4 =%x)\n",dirname,val4);
    setITCEnabledStatus(pru,prudir,0);
    BUG_ON(!t);
    ++t->mSyncFailureAnnouncements;
    break;

  case 'T': // Announcing timeout on pru,prudir
    DBGPRINTK(DBG_PKT_ROUTE, KERN_INFO "%s: Timeout\n",dirname);
    setITCEnabledStatus(pru,prudir,0);
    BUG_ON(!t);
    ++t->mTimeoutAnnouncements;
    break;

  case 'M': // val4 is three-bits of per-pru disabled status
    // 'M' comes from the linux thread so prudir, above, is 3
    {
      int i;

      for (i = 0; i < 3; ++i) {
        int enabled = !(val4&(1<<i));
        setITCEnabledStatus(pru,i,enabled);
      }
    }
    break;
  }
}

static int itc_pkt_cb(struct rpmsg_device *rpdev,
                      void *data , int len , void *priv,
                      u32 src )
{
  ITCPRUDeviceState * prudevstate = dev_get_drvdata(&rpdev->dev);
  ITCCharDeviceState * cdevstate = (ITCCharDeviceState *) prudevstate;
  int minor = MINOR(cdevstate->mDevt);

  if (minor < 0 || minor > 1) {
    printk(KERN_ERR "itc_pkt_cb received %d from %d\n",len, minor);
  }
  
  BUG_ON(minor < 0 || minor > 1);

  DBGPRINT_HEX_DUMP(DBG_PKT_RCVD,
                    KERN_INFO, minor ? "<pru1: " : "<pru0: ",
                    DUMP_PREFIX_NONE, 16, 1,
                    data, len, true);

  if (len > 1) {
    u8 * bytes = (u8*) data;
    u8 type = bytes[0];
    u8 byte1 = bytes[1];

    if (type&PKT_HDR_BITMASK_STANDARD) {   // Standard packet

      if (!(type&PKT_HDR_BITMASK_LOCAL)) { // Standard routed packet

        u32 dir8 = type&PKT_HDR_BITMASK_DIR;
        u32 dir6 = mapDir8ToDir6(dir8);
        BUG_ON(dir6 >= DIR6_COUNT);

        if (type&PKT_HDR_BITMASK_OVERRUN) {
          printk(KERN_ERR "(%s) Packet overrun reported on size %d packet\n", getDir8Name(type&0x7), len);
        }

        if (type&PKT_HDR_BITMASK_ERROR) {
          printk(KERN_ERR "(%s) Packet error reported on size %d packet\n", getDir8Name(type&0x7),len);
          DBGPRINT_HEX_DUMP(DBG_PKT_ERROR,
                            KERN_INFO, minor ? "<pru1: " : "<pru0: ",
                            DUMP_PREFIX_NONE, 16, 1,
                            bytes, len, true);
        }

        if (len > ITC_MAX_PACKET_SIZE) {
          printk(KERN_ERR "(%s) Truncating overlength (%d) packet\n",getDir8Name(type&0x7),len);
          len = ITC_MAX_PACKET_SIZE;
        }

        { /* Deliver to appropriate device */

          ITCPktDeviceState * pktdev = 0;
          ITCPacketBuffer * ipb;
          bool urgent = type&PKT_HDR_BITMASK_URGENT;
          u32 idx = urgent ? TRAFFIC_URGENT : TRAFFIC_BULK;
          ITCTrafficStats * t = getITCTrafficStatsFromDir8(dir8);

          t->mCounts[idx].mPacketsReceived++;
          t->mCounts[idx].mBytesReceived += len;

          /* Set up pktdev depending on destination */
          if (!urgent)  /* bulk traffic is all delivered to /dev/itc/bulk */
            pktdev = S.mPktDeviceState[0]; /* 0==/dev/itc/bulk */
          else if (!(byte1&PKT_HDR_BYTE1_BITMASK_MFM)) /* urgent non-mfm is flash traffic */
            pktdev = S.mPktDeviceState[1]; /* 1==/dev/itc/flash */
          else if (!(byte1&PKT_HDR_BYTE1_BITMASK_KITC)) { /* mfm non-kitc is event traffic */
            pktdev = &S.mMFMDeviceState[dir6]->mPktDevState;
          } else /* URG & MFM & ITC are all 1 */{
            handleKITCPacket(S.mMFMDeviceState[dir6], bytes, len);
            /*pktdev remains 0*/
          }

          if (pktdev) {
            ipb = &pktdev->mUserIB;

            if (kfifo_avail(&ipb->mFIFO) < len) 
              DBGPRINTK(DBG_PKT_DROPS,
                        KERN_INFO "(%s) Inbound %s queue full, dropping %s len=%d packet\n",
                        getDir8Name(type&0x7),
                        ipb->mName,
                        urgent ? "priority" : "bulk",
                        len);
            else {
              tpReportIfMatch(&ipb->mTraceInsert, pktdev->mCDevState.mName, true, data, len, ipb);

              kfifo_in(&ipb->mFIFO, data, len); 

              ADD_PKT_EVENT(makePktXfrEvent(PEV_XFR_FROM_PRU, urgent, log2in3(len), type&0x7));

              DBGPRINTK(DBG_PKT_RCVD,
                        KERN_INFO "Stashed %s/%d packet for pktdev %s ipb %s, waking %p\n",
                        strPktHdr(bytes[0]),
                        len,
                        pktdev->mCDevState.mName,
                        ipb->mName,
                        &ipb->mReaderQ);
            }
          
            wake_up_interruptible(&ipb->mReaderQ);
          }
        }
      } else {                             // Standard local packet
        ITCPacketBuffer * ipb;

        BUG_ON(!prudevstate);
        ipb = &prudevstate->mLocalIB;

        // Trace (LKM-handled) standard local packets as if they're
        // inserts to the LocalIB even though they never get
        // inserted..
        tpReportIfMatch(&ipb->mTraceInsert, minor == 0 ? "pru0/c3" : "pru1/c3", true, bytes, len, ipb);

        switch (type&PKT_HDR_BITMASK_LOCAL_TYPE) {

        default:
        case 0:
          printk(KERN_ERR "Illegal standard local packet %d\n",type&PKT_HDR_BITMASK_LOCAL_TYPE);
          break;

        case 1:
          printk(KERN_INFO "DEBUG%d %s\n",minor,&bytes[1]);
          break;

        case 2:
          printk(KERN_INFO "VALUE%d %s\n",minor,&bytes[1]);
          break;

        case 3:
          handleLocalStandard3(minor, bytes, len);
          break;
        }
      }
    } else { /* non-standard packets.  Deliver to /dev/itc/pru[01] */
      ITCPRUDeviceState * prudev = S.mPRUDeviceState[minor];
      ITCPacketBuffer * ipb;

      BUG_ON(!prudev);
      ipb = &prudev->mLocalIB;

      if (kfifo_avail(&ipb->mFIFO) < len) 
        DBGPRINTK(DBG_PKT_DROPS,
                  KERN_INFO "(%s) Inbound queue full, dropping PRU%d len=%d packet\n",
                  getDir8Name(type&0x7), minor, len);
      else {
        u32 copied;

        tpReportIfMatch(&ipb->mTraceInsert, prudev->mCDevState.mName, true, data, len, ipb);

        copied = kfifo_in(&ipb->mFIFO, data, len);
        DBGPRINTK(DBG_PKT_RCVD,
                  KERN_INFO "Stashed %d for %s/%d packet for prudev %s ipb %s, waking %p\n",
                  copied,
                  strPktHdr(bytes[0]),
                  len,
                  prudev->mCDevState.mName,
                  ipb->mName,
                  &ipb->mReaderQ);
        wake_up_interruptible(&ipb->mReaderQ);
      }
    }
  }
  return 0;
}

static void initITCPacketBuffer(ITCPacketBuffer * ipb, const char * ipbname, bool routed, bool priority, int minor, int buffer) {
  BUG_ON(!ipb);
  ipb->mMinor = minor;
  ipb->mBuffer = buffer;
  ipb->mRouted = routed;
  ipb->mPriority = priority;
  strncpy(ipb->mName, ipbname,DBG_NAME_MAX_LENGTH);
  mutex_init(&ipb->mLock);
  init_waitqueue_head(&ipb->mReaderQ);
  init_waitqueue_head(&ipb->mWriterQ);
  INIT_KFIFO(ipb->mFIFO);
}

static ITCPktDeviceState * makeITCPktDeviceState(struct device * dev,
                                                 int minor_to_create,
                                                 int * err_ret)
{
  ITCCharDeviceState* cdev = makeITCCharDeviceState(dev, sizeof(ITCPktDeviceState), minor_to_create, err_ret);
  ITCPktDeviceState* pktdev = (ITCPktDeviceState*) cdev;
  initITCPacketBuffer(&pktdev->mUserIB, "mUserIB", false, false, minor_to_create, BUFFERSET_U);
  return pktdev;
}

static ITCPRUDeviceState * makeITCPRUDeviceState(struct device * dev,
                                                 int minor_to_create,
                                                 int * err_ret)
{
  ITCCharDeviceState* cdev = makeITCCharDeviceState(dev, sizeof(ITCPRUDeviceState), minor_to_create, err_ret);
  ITCPRUDeviceState* prudev = (ITCPRUDeviceState*) cdev;
  prudev->mRpmsgDevice = 0; /* caller inits later */
  initITCPacketBuffer(&prudev->mLocalIB,"mLocalIB",false,false, minor_to_create, BUFFERSET_L);
  initITCPacketBuffer(&prudev->mPriorityOB,"mPriorityOB",true,true, minor_to_create, BUFFERSET_P);
  initITCPacketBuffer(&prudev->mBulkOB,"mBulkOB",true,false, minor_to_create, BUFFERSET_B);
  return prudev;
}

static ITCEvtDeviceState * makeITCEvtDeviceState(struct device * dev,
                                                 int minor_to_create,
                                                 int * err_ret)
{
  ITCCharDeviceState* cdev = makeITCCharDeviceState(dev, sizeof(ITCEvtDeviceState), minor_to_create, err_ret);
  ITCEvtDeviceState* evtdev = (ITCEvtDeviceState*) cdev;
  initITCPktEventState(&evtdev->mPktEvents);
  return evtdev;
}

static ITCMFMDeviceState * makeITCMFMDeviceState(struct device * dev,
                                                 int minor_to_create,
                                                 int * err_ret)
{
  ITCCharDeviceState* cdev = makeITCCharDeviceState(dev, sizeof(ITCMFMDeviceState), minor_to_create, err_ret);
  ITCMFMDeviceState* mfmdev = (ITCMFMDeviceState*) cdev;
  ITCPktDeviceState* pktdev = (ITCPktDeviceState*) mfmdev;
  initITCPacketBuffer(&pktdev->mUserIB, "mUserIB",false,false,minor_to_create,BUFFERSET_P);
  mfmdev->mStale = false;
  BUG_ON(minor_to_create < PKT_MINOR_MFM_ET || minor_to_create > PKT_MINOR_MFM_NE);
  mfmdev->mDir6 = minor_to_create - PKT_MINOR_MFM_ET;
  initITCLevelState(&mfmdev->mLevelState);
  return mfmdev;
}

/*
 * driver probe function
 */

static int itc_pkt_probe(struct rpmsg_device *rpdev)
{
  int ret;
  ITCPRUDeviceState *prudevstate;
  int minor_obtained;

  printk(KERN_INFO "ZORG itc_pkt_probe dev=%p\n", &rpdev->dev);

  dev_info(&rpdev->dev, "new channel: 0x%x -> 0x%x\n", rpdev->src, rpdev->dst);

  minor_obtained = rpdev->dst - 30;
  if (minor_obtained < 0 || minor_obtained > 1) {
    dev_err(&rpdev->dev, "Failed : Unrecognized destination %d\n",
            rpdev->dst);
    return -ENODEV;
  }

  /* If first minor, first open packet, mfm, and evt devices */
  if (S.mOpenPRUMinors == 0) {

    unsigned i;
    for (i = 0; i <= 1; ++i) { /* Make PKT_MINOR_BULK & PKT_MINOR_FLASH */
      unsigned minor_to_create = i + PKT_MINOR_BULK;

      printk(KERN_INFO "ZROG making minor %d (on minor_obtained %d)\n", minor_to_create, minor_obtained);

      S.mPktDeviceState[i] = makeITCPktDeviceState(&rpdev->dev, minor_to_create, &ret);

      printk(KERN_INFO "GROZ made minor %d=%p (err %d)SLORG\n", minor_to_create, S.mPktDeviceState[i], ret);

      if (!S.mPktDeviceState[i])
        return ret;
    }

    for (i = 0; i < EVT_MINORS; ++i) { /* Make PKT_MINOR_EVT and PKT_MINOR_ITC_EVT */
      unsigned minor_to_create = i + PKT_MINOR_EVT;

      printk(KERN_INFO "ZREG making minor %d (on minor_obtained %d)\n", minor_to_create, minor_obtained);

      S.mEvtDeviceState[i] = makeITCEvtDeviceState(&rpdev->dev, minor_to_create, &ret);

      printk(KERN_INFO "GREZ made minor %d=%p (err %d)SLORG\n", minor_to_create, S.mEvtDeviceState[i], ret);

      if (!S.mEvtDeviceState[i])
        return ret;
    }

    for (i = DIR6_ET; i <= DIR6_NE; ++i) { /* Make PKT_MINOR_MFM_ET .. PKT_MINOR_MFM_NE */
      unsigned minor_to_create = i + PKT_MINOR_MFM_BASE;

      printk(KERN_INFO "MREG making minor %d (on minor_obtained %d)\n", minor_to_create, minor_obtained);

      S.mMFMDeviceState[i] = makeITCMFMDeviceState(&rpdev->dev, minor_to_create, &ret);

      printk(KERN_INFO "MREZ made minor %d=%p (err %d)MLORG\n", minor_to_create, S.mMFMDeviceState[i], ret);

      if (!S.mMFMDeviceState[i])
        return ret;
    }
  }

  printk(KERN_INFO "GORZ minor_obtained %d\n",minor_obtained);

  BUG_ON(S.mPRUDeviceState[minor_obtained]);

  prudevstate = makeITCPRUDeviceState(&rpdev->dev, minor_obtained, &ret);

  printk(KERN_INFO "BLURGE back with devstate=%p\n",prudevstate);

  if (!prudevstate)
    return ret;

  prudevstate->mRpmsgDevice = rpdev;

  S.mPRUDeviceState[minor_obtained] = prudevstate;

  ++S.mOpenPRUMinors;

  /* send empty message to give PRU src & dst info*/
  {
    char buf[10];
    printk(KERN_INFO "BLURGE sending on buf=%p\n",buf);

    ret = sendMsgToPRU(minor_obtained,0,buf,10, "%s",""); /* grr..gcc warns on "" as format string */
    printk(KERN_INFO "RECTOBLURGE back with buf='%s'\n",buf);
  }

  if (ret) {
    struct cdev * cdev = &prudevstate->mCDevState.mLinuxCdev;
    struct device * dev = prudevstate->mCDevState.mLinuxDev;
    dev_err(dev, "Opening transmission on rpmsg bus failed %d\n",ret);
    ret = PTR_ERR(dev);
    cdev_del(cdev);
  } else {
    /* When last PRU is booted, start the shipping thread */
    if (S.mOpenPRUMinors == PRU_MINORS) {
      createITCThreads(&S);
      printk(KERN_INFO "KKOO\n");
    }
  }

  return ret;
}

static const struct rpmsg_device_id rpmsg_driver_itc_pkt_id_table[] = {
  { .name = "itc-pkt" },
  { },
};

MODULE_DEVICE_TABLE(rpmsg, rpmsg_driver_itc_pkt_id_table);

static ssize_t itc_pkt_read_poop_data(struct file *filp, struct kobject *kobj,
                                      struct bin_attribute *attr,
                                      char *buffer, loff_t offset, size_t count)
{
  BUG_ON(!kobj);
  printk(KERN_INFO "read poop data kobject %p\n", kobj);

  if (offset) return 0;

  snprintf(buffer,count,"P0123456789oop");

  return strlen(buffer);
}

static ssize_t itc_pkt_write_poop_data(struct file *filp, struct kobject *kobj,
                                       struct bin_attribute *attr,
                                       char *buffer, loff_t offset, size_t count)
{
  printk(KERN_INFO "write poop data kobject %p/(%s/%u)\n", kobj,buffer,count);

  return count;
}

static BIN_ATTR(poop_data, 0644, itc_pkt_read_poop_data, itc_pkt_write_poop_data, 0);

/*DEVICE ATTRIBUTE STUFF*/
static struct attribute *itc_pkt_attrs[] = {
  NULL,
};

static struct bin_attribute * itc_pkt_bin_attrs[] = {
  &bin_attr_poop_data,
  NULL,
};

static const struct attribute_group itc_pkt_group = {
  .attrs = itc_pkt_attrs,
  .bin_attrs = itc_pkt_bin_attrs,
};

static const struct attribute_group * itc_pkt_groups[] = {
  &itc_pkt_group,
  NULL,
};

static struct class itc_pkt_class_instance = {
  .name = "itc_pkt",
  .owner = THIS_MODULE,
  .class_groups = class_itc_pkt_groups,
  .dev_groups = itc_pkt_groups,
};

/* Clearly I don't get mutex_init.  It uses a static local supposedly
   to associate a 'unique' key with each mutex.  But if mutex_init is
   called in a loop (as in make_itc_minor, implicitly, below), then
   we'll only get one key for all the mutexes, right?

   Clearly I don't get mutex_init.  But in my typical paranoid fugue
   that surrounds any use of locking sutff, I want to arranging that
   each mutex gets a separate mutex_init invocation, by doing
   something like:

   switch (minor_obtained) {
   case 0: mutex_init(&devstate->specialLock); break;
   case 1: mutex_init(&devstate->specialLock); break;
   case 2: mutex_init(&devstate->specialLock); break;
   default: BUG_ON(1);
   }

   But that's insane, right?  Clearly, I don't get mutex_init.

   Reading Documentation/locking/lockdep-design.txt helps some but
   still leaves me confused.  The key identifies a 'class' of locks,
   so with the switch code above I'd generate three lock classes
   each with one lock instance, while with the code below I'm
   generating one class with three instances.  On the one hand,
   lockdep-design says this:

   > For example a lock in the inode struct is one class, while each
   > inode has its own instantiation of that lock class.

   which makes it sound like of course I should have just one class
   for my pitiful little three lock instances.  But on the other
   hand lockdep-design also says this:

   > The same lock-class must not be acquired twice, because this
   > could lead to lock recursion deadlocks.

   which sounds to me like if I make a single lock class, then when
   someone's holding the PRU0 lock nobody else can acquire the PRU1
   lock, since that would be the 'same lock-class' being acquired
   twice.

   But that can't be what it means, right, or else having one inode
   locked would block all the rest?  'Acquiring a lock-class' must
   mean something other than 'acquiring a lock instance of a given
   class'.  Or something.  But I'm going with the single shared
   lock-class here, and May God Have Mercy On Our Heathen Souls.

   And, umm, Clearly I Don't Get mutex_init.
*/

ITCCharDeviceState * makeITCCharDeviceState(struct device * dev,
                                            unsigned struct_size,
                                            int minor_obtained,
                                            int * err_ret)
{
  ITCCharDeviceState * cdevstate;
  enum { BUFSZ = 32 };
  char devname[BUFSZ];
  int ret;

  BUG_ON(!err_ret);

  BUG_ON(struct_size < sizeof(ITCCharDeviceState));

  switch (minor_obtained) {
  case PKT_MINOR_BULK: snprintf(devname,BUFSZ,"itc!bulk"); break;
  case PKT_MINOR_FLASH: snprintf(devname,BUFSZ,"itc!flash"); break;
  case PKT_MINOR_EVT: snprintf(devname,BUFSZ,"itc!pktevents"); break;
  case PKT_MINOR_ITC_EVT: snprintf(devname,BUFSZ,"itc!itcevents"); break;
  case PRU_MINOR_PRU0:
  case PRU_MINOR_PRU1:
    snprintf(devname,BUFSZ,"itc!pru!%d",minor_obtained);
    break;
  case PKT_MINOR_MFM_ET: snprintf(devname,BUFSZ,"itc!mfm!ET"); break;
  case PKT_MINOR_MFM_SE: snprintf(devname,BUFSZ,"itc!mfm!SE"); break;
  case PKT_MINOR_MFM_SW: snprintf(devname,BUFSZ,"itc!mfm!SW"); break;
  case PKT_MINOR_MFM_WT: snprintf(devname,BUFSZ,"itc!mfm!WT"); break;
  case PKT_MINOR_MFM_NW: snprintf(devname,BUFSZ,"itc!mfm!NW"); break;
  case PKT_MINOR_MFM_NE: snprintf(devname,BUFSZ,"itc!mfm!NE"); break;
    
  default: BUG_ON(1);
  }

  printk(KERN_INFO "ZERGIN: makeITCCharDeviceState(%p,%u,%d,%p) for %s\n", dev, struct_size, minor_obtained, err_ret, devname);

  cdevstate = devm_kzalloc(dev, struct_size, GFP_KERNEL);
  if (!cdevstate) {
    ret = -ENOMEM;
    goto fail_kzalloc;
  }

  strncpy(cdevstate->mName,devname,DBG_NAME_MAX_LENGTH);
  cdevstate->mDevt = MKDEV(MAJOR(S.mMajorDevt), minor_obtained);

  printk(KERN_INFO "INITTING /dev/%s with minor_obtained=%d (dev=%p)\n", devname, minor_obtained, dev);

  cdev_init(&cdevstate->mLinuxCdev, itc_pkt_fops_ptrs[minor_obtained]);
  cdevstate->mLinuxCdev.owner = THIS_MODULE;
  ret = cdev_add(&cdevstate->mLinuxCdev, cdevstate->mDevt,1);

  if (ret) {
    dev_err(dev, "Unable to init cdev\n");
    goto fail_cdev_init;
  }

  printk(KERN_INFO "RZOG Back from cdev_init+cdev_add\n");

  printk(KERN_INFO "GRZO going to device_create(%p,%p,devt=(%d:%d),NULL,%s)\n",
         &itc_pkt_class_instance,
         dev,
         MAJOR(cdevstate->mDevt), MINOR(cdevstate->mDevt),
         devname);

  cdevstate->mLinuxDev = device_create(&itc_pkt_class_instance,
                                       dev,
                                       cdevstate->mDevt, NULL,
                                       devname);

  printk(KERN_INFO "GOZR Back from device_create dev=%p\n", cdevstate->mLinuxDev);

  if (IS_ERR(cdevstate->mLinuxDev)) {
    dev_err(dev, "Failed to create device file entries\n");
    ret = PTR_ERR(cdevstate->mLinuxDev);
    goto fail_device_create;
  }

  dev_set_drvdata(dev, cdevstate);
  dev_info(dev, "ITCCharDeviceState early init done on /dev/%s",devname);

  *err_ret = ret;
  return cdevstate;

 fail_device_create:
  cdev_del(&cdevstate->mLinuxCdev);

 fail_cdev_init:

 fail_kzalloc:
  *err_ret = ret;
  return 0;
}

static void unmakePacketBuffer(ITCPacketBuffer * ipb) {
  mutex_destroy(&ipb->mLock);
}

static void unmakePktEventState(ITCPktEventState * pes) {
  mutex_destroy(&pes->mPktEventReadMutex);
}

static void unmakeITCCharDeviceState(ITCCharDeviceState * cdevstate) {
  device_destroy(&itc_pkt_class_instance, cdevstate->mDevt);
  cdev_del(&cdevstate->mLinuxCdev);
}

static void unmakeITCPktDeviceState(ITCPktDeviceState * pktdevstate) {
  unmakePacketBuffer(&pktdevstate->mUserIB);
  unmakeITCCharDeviceState((ITCCharDeviceState *) pktdevstate);
}

static void unmakeITCEvtDeviceState(ITCEvtDeviceState * evtdevstate) {
  unmakePktEventState(&evtdevstate->mPktEvents);
  unmakeITCCharDeviceState((ITCCharDeviceState *) evtdevstate);
}

static void unmakeITCMFMDeviceState(ITCMFMDeviceState * mfmdevstate) {
  ITCPktDeviceState * pktdev = (ITCPktDeviceState*) mfmdevstate;
  unmakePacketBuffer(&pktdev->mUserIB);
  unmakeITCCharDeviceState((ITCCharDeviceState *) mfmdevstate);
}

static void unmakeITCPRUDeviceState(ITCPRUDeviceState * prudevstate) {
  BUG_ON(S.mOpenPRUMinors < 1);
  unmakePacketBuffer(&prudevstate->mLocalIB);
  unmakePacketBuffer(&prudevstate->mPriorityOB);
  unmakePacketBuffer(&prudevstate->mBulkOB);
  unmakeITCCharDeviceState((ITCCharDeviceState *) prudevstate);
  --S.mOpenPRUMinors;
}

static void itc_pkt_remove(struct rpmsg_device *rpdev) {

  ITCPRUDeviceState * prudevstate = dev_get_drvdata(&rpdev->dev);

  /* thread is last made so first destroyed */
  if (S.mOpenPRUMinors == PRU_MINORS) {
    destroyITCThreads(&S);
  }

  unmakeITCPRUDeviceState(prudevstate);

  if (S.mOpenPRUMinors == 0) {
    int i;
    for (i = MFM_MINORS - 1; i >= 0; --i)
      unmakeITCMFMDeviceState(S.mMFMDeviceState[i]);
    for (i = EVT_MINORS - 1; i >= 0; --i)
      unmakeITCEvtDeviceState(S.mEvtDeviceState[i]);
    for (i = PKT_MINORS - 1; i >= 0; --i)
      unmakeITCPktDeviceState(S.mPktDeviceState[i]);
  }
}

static struct rpmsg_driver itc_pkt_driver = {
  .drv.name	= KBUILD_MODNAME,
  .drv.owner	= THIS_MODULE,
  .id_table	= rpmsg_driver_itc_pkt_id_table,
  .probe	= itc_pkt_probe,
  .callback	= itc_pkt_cb,
  .remove	= itc_pkt_remove,
};

static int __init itc_pkt_init (void)
{
  int ret;

  printk(KERN_INFO "ZORG itc_pkt_init\n");

  initITCModuleState(&S);

  printk(KERN_INFO "OOKE %08x\n", S.mItcEnabledStatus);

  ret = class_register(&itc_pkt_class_instance);
  if (ret) {
    pr_err("Failed to register class\n");
    goto fail_class_register;
  }

  printk(KERN_INFO "KOOK %08x\n", S.mItcEnabledStatus);

  /*  itc_pkt_class_instance.dev_groups = itc_pkt_groups;   */

  ret = alloc_chrdev_region(&S.mMajorDevt, 0,
                            MINOR_DEVICES, "itc_pkt");
  if (ret) {
    pr_err("Failed to allocate chrdev region\n");
    goto fail_alloc_chrdev_region;
  }

  printk(KERN_INFO "OKKO\n");

  ret = register_rpmsg_driver(&itc_pkt_driver);
  if (ret) {
    pr_err("Failed to register the driver on rpmsg bus");
    goto fail_register_rpmsg_driver;
  }

  printk(KERN_INFO "KOKO\n");


  return 0;

 fail_register_rpmsg_driver:
  unregister_chrdev_region(S.mMajorDevt,
                           MINOR_DEVICES);
 fail_alloc_chrdev_region:
  class_unregister(&itc_pkt_class_instance);
 fail_class_register:
  return ret;
}


static void __exit itc_pkt_exit (void)
{
  unregister_rpmsg_driver(&itc_pkt_driver);
  class_unregister(&itc_pkt_class_instance);
  unregister_chrdev_region(S.mMajorDevt,
                           MINOR_DEVICES);
}

module_init(itc_pkt_init);
module_exit(itc_pkt_exit);

MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("Dave Ackley <ackley@ackleyshack.com>");
MODULE_DESCRIPTION("T2 intertile packet communications subsystem");  ///< modinfo description

MODULE_VERSION("0.8");            ///< 0.8 for /dev/itc/itcevents
/// 0.7 for KITCs
/// 0.6 for /dev/itc/pktevents
/// 0.5 for /dev/itc/mfm
/// 0.4 for general internal renaming and reorg
/// 0.3 for renaming to itc_pkt
/// 0.2 for initial import

/////ADDITIONAL COPYRIGHT INFO

/* This software is based in part on 'rpmsg_pru_parallel_example.c',
 * which is: Copyright (C) 2016 Zubeen Tolani <ZeekHuge -
 * zeekhuge@gmail.com> and also licensed under the terms of the GNU
 * General Public License version 2.
 *
 */

/* And that software, in turn, was based on examples from the
 * 'pru-software-support-package', which includes the following:
 */

/*
 * Copyright (C) 2016 Texas Instruments Incorporated - http://www.ti.com/
 *
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *	* Redistributions of source code must retain the above copyright
 *	  notice, this list of conditions and the following disclaimer.
 *
 *	* Redistributions in binary form must reproduce the above copyright
 *	  notice, this list of conditions and the following disclaimer in the
 *	  documentation and/or other materials provided with the
 *	  distribution.
 *
 *	* Neither the name of Texas Instruments Incorporated nor the names of
 *	  its contributors may be used to endorse or promote products derived
 *	  from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
