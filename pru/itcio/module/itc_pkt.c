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

#include "itc_pkt.h"

static bool shipCurrentOBPackets(void) ;

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

static ITCModuleState S;  /* Our module-global state */

static int mapPruAndPrudirToDirNum(int pru, int prudir) {
  switch ((pru<<3)|prudir) {
#define XX(dir)                                                         \
  case (ITC_DIR_TO_PRU(dir)<<3) | ITC_DIR_TO_PRUDIR(dir): return ITC_DIR_TO_DIR_NUM(dir);
FOR_XX_IN_ITC_ALL_DIR
#undef XX
  default: return -1;
  }
}

#define STRPKTHDR_BUF_SIZE 8
#define STRPKTHDR_MAX_BUFS 10
static char * strPktHdr(u8 hdr) {
  static char buf[STRPKTHDR_BUF_SIZE][STRPKTHDR_MAX_BUFS];
  static u32 nextbuf = STRPKTHDR_MAX_BUFS;
  char * p = &buf[0][nextbuf];
  if (++nextbuf >= STRPKTHDR_MAX_BUFS) nextbuf = 0;
  
  if (isprint(hdr))
    sprintf(p,"0x%02x'%c'",hdr,hdr);
  else
    sprintf(p,"0x%02x",hdr);
  return p;
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
  for (i = 0; i < 2; ++i)
    initITCTrafficCounts(&s->mCounts[i]);
}

static ITCTrafficStats * getITCTrafficStatsFromDir(u32 dirnum)
{
  BUG_ON(dirnum >= ITC_DIR_COUNT);
  return &S.mItcStats[dirnum];
}

static ITCTrafficStats * getITCTrafficStats(u8 pru, u8 prudir)
{
  int dir = mapPruAndPrudirToDirNum(pru,prudir);
  if (dir < 0) return 0;
  return getITCTrafficStatsFromDir(dir);
}

static void wakeOBPktShipper(void) {
  if (S.mShipOBPktTask) 
    wake_up_process(S.mShipOBPktTask);
}

static int itcOBPktThreadRunner(void *arg) {

  printk(KERN_INFO "itcOBPktThreadRunner: Started\n");

  while(!kthread_should_stop()) {    /* Returns true when kthread_stop() is called */
    int waitms = 100;                /* producers kick us so timeout should be rare backstop */
    set_current_state(TASK_RUNNING);
    if (shipCurrentOBPackets()) waitms = 1; /* Except short wait if txbufs ran out */
    msleep_interruptible(waitms);      
  }
  printk(KERN_INFO "itcOBPktThreadRunner: Stopping by request\n");
  return 0;
}

static void initITCModuleState(ITCModuleState *s)
{
  {
    unsigned i;
    for (i = 0; i < PRU_MINORS; ++i) s->mPRUDeviceState[i] = 0;
    for (i = 0; i < PKT_MINORS; ++i) s->mPktDeviceState[i] = 0;
    for (i = 0; i < ITC_DIR_COUNT; ++i) initITCTrafficStats(&s->mItcStats[i], i);
  }

#if MORE_DEBUGGING
  s->mDebugFlags = 0xf; /* some default debugging */
#else
  s->mDebugFlags = 0;  /* or no default debugging */
#endif

  s->mOpenPRUMinors = 0;
  s->mItcEnabledStatus = 0;  // Assume all dirs disabled

}

static void createITCThreads(ITCModuleState *s)
{
  init_waitqueue_head(&s->mOBWaitQueue);

  s->mShipOBPktTask = kthread_run(itcOBPktThreadRunner, NULL, "ITC_Pkt_Shipper");
  if (IS_ERR(s->mShipOBPktTask)) {
    printk(KERN_ALERT "ITC: Thread creation failed\n");
    /*return PTR_ERR(s->mShipOBPktTask); */
  }
}

static void destroyITCThreads(ITCModuleState *s) {
  BUG_ON(!s->mShipOBPktTask);
  kthread_stop(s->mShipOBPktTask);    /* Kill the shipping thread */
  s->mShipOBPktTask = 0;
}

static void destroyITCModuleState(ITCModuleState *s) {
  destroyITCThreads(s);
}

/* return size of packet sent, 0 if nothing to send, < 0 if problem */
static int sendPacketViaRPMsg(ITCPRUDeviceState * prudev, ITCPacketBuffer * ipb) {
  struct rpmsg_channel * chnl;
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

  chnl = prudev->mRpmsgChannel;
  BUG_ON(!chnl);

  DBGPRINTK(DBG_PKT_ROUTE,
            KERN_INFO "Trying to send %s/%d packet via prudev %s %s\n",
            strPktHdr(prudev->mTempPacketBuffer[0]),
            pktlen,
            prudev->mCDevState.mName,
            ipb->mName);

  ret = rpmsg_trysend(chnl, prudev->mTempPacketBuffer, pktlen);
  if (ret < 0) return ret;      /* send failed; -ENOMEM means no tx buffers */

  if (ipb->mRouted) { /* Do stats on routed buffers */
    u8 itcDir = prudev->mTempPacketBuffer[0]&0x7;  /* Get direction from header */
    ITCTrafficStats * t = getITCTrafficStatsFromDir(itcDir);
    u32 index = ipb->mPriority ? 1 : 0;
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
  BUG_ON(!prudevstate->mRpmsgChannel);

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
  bool noTxBuffer = false;
  unsigned i;
  unsigned idx = prandom_u32_max(2);

  for (i = 0; i < 2; ++i, idx = 1-idx) {
    int ret;
    while ( (ret = shipAPacketToPRU(S.mPRUDeviceState[idx])) == 0 ) { /* empty */ }
    if (ret == -ENOMEM) noTxBuffer = true;
  }

  return noTxBuffer;
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

  BUG_ON(!prudevstate->mRpmsgChannel);

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

  ret = rpmsg_send(prudevstate->mRpmsgChannel, buf, len);

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
static ssize_t itc_pkt_class_store_poke(struct class *c,
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

static ssize_t itc_pkt_class_read_status(struct class *c,
                                        struct class_attribute *attr,
                                        char *buf)
{
  sprintf(buf,"%08x\n",S.mItcEnabledStatus);
  return strlen(buf);
}


static ssize_t itc_pkt_class_read_statistics(struct class *c,
                                             struct class_attribute *attr,
                                             char *buf)
{
  /* We have a PAGE_SIZE (== 4096) in buf, but won't get near that.  Max size
     presently is something like ( 110 + 8 * ( 2 + 3 * 11 + 8 * 11) ) < 1100 */
  int len = 0;
  int itc, speed;
  len += sprintf(&buf[len], "dir psan sfan toan blkbsent blkbrcvd blkpsent blkprcvd pribsent pribrcvd pripsent priprcvd\n");
  for (itc = 0; itc < ITC_DIR_COUNT; ++itc) {
    ITCTrafficStats * t = &S.mItcStats[itc];
    len += sprintf(&buf[len], "%u %u %u %u",
                   itc,
                   t->mPacketSyncAnnouncements,
                   t->mSyncFailureAnnouncements,
                   t->mTimeoutAnnouncements
                   );
    for (speed = 0; speed < 2; ++speed) {
      ITCTrafficCounts *c = &t->mCounts[speed];
      len += sprintf(&buf[len], " %u %u %u %u",
                     c->mBytesSent, c->mBytesReceived,
                     c->mPacketsSent, c->mPacketsReceived);
    }
    len += sprintf(&buf[len], "\n");
  }
  return len;
}

static int sprintPktBufInfo(char * buf, int len, ITCPacketBuffer * p)
{
  len += sprintf(&buf[len]," %u %u %u",
                 kfifo_len(&p->mFIFO),
                 !list_empty(&p->mReaderQ.task_list),
                 !list_empty(&p->mWriterQ.task_list));
  return len;
}


static ssize_t itc_pkt_class_read_pru_bufs(struct class *c,
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

static ssize_t itc_pkt_class_read_pkt_bufs(struct class *c,
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


static ssize_t itc_pkt_class_read_debug(struct class *c,
                                        struct class_attribute *attr,
                                        char *buf)
{
  sprintf(buf,"%x\n",S.mDebugFlags);
  return strlen(buf);
}

static ssize_t itc_pkt_class_store_debug(struct class *c,
                                         struct class_attribute *attr,
                                         const char *buf,
                                         size_t count)
{
  unsigned tmpdbg;
  if (count == 0) return -EINVAL;

  if (sscanf(buf,"%x",&tmpdbg) == 1) {
    printk(KERN_INFO "set debug %x\n",tmpdbg);
    S.mDebugFlags = tmpdbg;
    return count;
  }
  return -EINVAL;
}

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
static ssize_t itc_pkt_class_read_##dir##_##pin(struct class *c,        \
                                                struct class_attribute *attr, \
                                                char *buf)              \
{                                                                       \
  return itc_pin_read_handler(ITC_DIR_TO_PRU(dir),                      \
                              ITC_DIR_TO_PRUDIR(dir),                   \
                              ITC_DIR_AND_PIN_TO_R31_BIT(dir,pin),      \
                              c,attr,buf);                              \
}                                                                       \

#define ITC_OUTPUT_PIN_FUNC(dir,pin)                                    \
static ssize_t itc_pkt_class_write_##dir##_##pin(struct class *c,       \
                                                 struct class_attribute *attr, \
                                                 const char *buf,       \
                                                 size_t count)          \
{                                                                       \
  return itc_pin_write_handler(ITC_DIR_TO_PRU(dir),                     \
                               ITC_DIR_TO_PRUDIR(dir),                  \
                               ITC_DIR_AND_PIN_TO_R30_BIT(dir,pin),     \
                               c,attr,buf,count);                       \
}                                                                       \


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
  __ATTR(dir##_##pin, 0444, itc_pkt_class_read_##dir##_##pin, NULL)
/* output pins are read-write */
#define ITC_OUTPUT_PIN_ATTR(dir,pin) \
  __ATTR(dir##_##pin, 0644, NULL, itc_pkt_class_write_##dir##_##pin)
#define XX(dir) \
  ITC_OUTPUT_PIN_ATTR(dir,TXRDY), \
  ITC_OUTPUT_PIN_ATTR(dir,TXDAT), \
  ITC_INPUT_PIN_ATTR(dir,RXRDY), \
  ITC_INPUT_PIN_ATTR(dir,RXDAT), \

static struct class_attribute itc_pkt_class_attrs[] = {
  FOR_XX_IN_ITC_ALL_DIR
  __ATTR(poke, 0200, NULL, itc_pkt_class_store_poke),
  __ATTR(debug, 0644, itc_pkt_class_read_debug, itc_pkt_class_store_debug),
  __ATTR(status, 0444, itc_pkt_class_read_status, NULL),
  __ATTR(statistics, 0444, itc_pkt_class_read_statistics, NULL),
  __ATTR(pru_bufs, 0444, itc_pkt_class_read_pru_bufs, NULL),
  __ATTR(pkt_bufs, 0444, itc_pkt_class_read_pkt_bufs, NULL),
  __ATTR_NULL,
};
#undef XX
/* GENERATE SYSFS CLASS ATTRIBUTES FOR ITC PINS: DONE */


/** @brief The callback function for when the device is opened
 *  What
 *  @param inodep A pointer to an inode object (defined in linux/fs.h)
 *  @param filep A pointer to a file object (defined in linux/fs.h)
 */
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

static const char * getDirName(u8 dir) {
  switch (dir) {
  case 0: return "N?";  /* what what? */
  case 1: return "NE";
  case 2: return "ET";
  case 3: return "SE";
  case 4: return "S?";  /* on T2 you say? */
  case 5: return "SW";
  case 6: return "WT";
  case 7: return "NW";
  }
  return "??";
}

static void setITCEnabledStatus(int pru, int prudir, int enabled) {
  int dirnum4 = mapPruAndPrudirToDirNum(pru,prudir)<<2;
  int bit = (0x1<<dirnum4);
  bool existing = (S.mItcEnabledStatus & bit);
  if (enabled && !existing) {
    S.mItcEnabledStatus |= bit;
    printk(KERN_INFO "ITCCHANGE:UP:%s\n",
           getDirName(mapPruAndPrudirToDirNum(pru,prudir)));
  } else if (!enabled && existing) {
    S.mItcEnabledStatus &= ~bit;
    printk(KERN_INFO "ITCCHANGE:DOWN:%s\n",
           getDirName(mapPruAndPrudirToDirNum(pru,prudir)));
  }
}

static int isITCEnabledStatusByITCDir(int itcDir) {
  int dirnum4 = itcDir<<2;
  return (S.mItcEnabledStatus>>dirnum4)&0x1;
}

static int routeOutboundStandardPacket(const unsigned char pktHdr, size_t pktLen)
{
  int itcDir;
  int newminor;
  if (pktLen == 0) return -EINVAL;
  if ((pktHdr & 0x80) == 0) return -ENXIO; /* only standard packets can be routed */
  itcDir = pktHdr & 0x7;
  if (!isITCEnabledStatusByITCDir(itcDir)) return -EHOSTUNREACH;

  switch (itcDir) {

  default: newminor = -ENODEV; break;
#define XX(dir) case ITC_DIR_TO_DIR_NUM(dir): newminor = ITC_DIR_TO_PRU(dir); break;
FOR_XX_IN_ITC_ALL_DIR
#undef XX
  }

  return newminor;
}

/** @brief This callback used when data is being written to the device
 *  from user space.  Note that although rpmsg allows messages over
 *  500 bytes long, so that's the limit for talking to a local PRU,
 *  intertile packets are limited to at most 255 bytes.  Here, that
 *  limit is enforced only for minor 2 (/dev/itc/packets) and minor 3
 *  (/dev/itc/mfm) because packets sent there are necessarily routable
 *  intertile.
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
  int minor = MINOR(cdevstate->mDevt);

  unsigned char pktHdr;
  bool bulkRate = true;  /* assume slow boat */

  DBGPRINTK(DBG_PKT_SENT, KERN_INFO "itc_pkt_write(%d) enter %s\n",minor, cdevstate->mName);

  if (count > RPMSG_MAX_PACKET_SIZE) {
    dev_err(cdevstate->mLinuxDev, "Data length (%d) exceeds rpmsg buffer size", count);
    return -EINVAL;
  }

  if (copy_from_user(&pktHdr, buf, 1)) { /* peek at first byte */
    dev_err(cdevstate->mLinuxDev, "Failed to copy data");
    return -EFAULT;
  }

  DBGPRINTK(DBG_PKT_SENT, KERN_INFO "itc_pkt_write(%d) read pkt type %s from user\n",minor, strPktHdr(pktHdr));

  if (minor == PKT_MINOR_ITC || minor == PKT_MINOR_MFM) {
    int newMinor = routeOutboundStandardPacket(pktHdr, count);

    DBGPRINTK(DBG_PKT_SENT, KERN_INFO "itc_pkt_write(%d) routing %s to minor %d\n",minor, strPktHdr(pktHdr), newMinor);

    //    printk(KERN_INFO "CONSIDERINGO ROUTINGO\n");
    if (newMinor < 0)
      return newMinor;          // bad routing

    if (count > ITC_MAX_PACKET_SIZE) {
      dev_err(cdevstate->mLinuxDev, "Routable packet size (%d) exceeds ITC length max (255)", count);
      return -EINVAL;
    }

    if (minor == PKT_MINOR_MFM) bulkRate = false; 

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

    DBGPRINTK(DBG_PKT_SENT, KERN_INFO "itc_pkt_write(%d) prewait %s\n",minor, ipb->mName);
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
      ret = kfifo_from_user(&ipb->mFIFO, buf, count, &copied);
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
    ret = kfifo_to_user(fifo, buf, count, &copied);
    DBGPRINTK(DBG_PKT_RCVD, KERN_INFO "itc_pkt_read(%d) post kfifo_to_user ret=%d copied=%d\n",
              minor,ret,copied);
  }
  mutex_unlock(&ipb->mLock);

  return ret ? ret : copied;
}


static const struct file_operations itc_pkt_fops = {
  .owner= THIS_MODULE,
  .open	= itc_pkt_open,
  .read = itc_pkt_read,
  .write= itc_pkt_write,
  .release= itc_pkt_release,
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

  dirname = getDirName(mapPruAndPrudirToDirNum(pru,prudir));

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

static void itc_pkt_cb(struct rpmsg_channel *rpmsg_chnl,
                       void *data , int len , void *priv,
                       u32 src )
{
  ITCPRUDeviceState * prudevstate = dev_get_drvdata(&rpmsg_chnl->dev);
  ITCCharDeviceState * cdevstate = (ITCCharDeviceState *) prudevstate;
  int minor = MINOR(cdevstate->mDevt);

  BUG_ON(minor < 0 || minor > 1);
  //  printk(KERN_INFO "Received %d from %d\n",len, minor);

  DBGPRINT_HEX_DUMP(DBG_PKT_RCVD,
                    KERN_INFO, minor ? "<pru1: " : "<pru0: ",
                    DUMP_PREFIX_NONE, 16, 1,
                    data, len, true);

  if (len > 0) {
    u8 * bytes = (u8*) data;
    u8 type = bytes[0];

    if (type&PKT_HDR_BITMASK_STANDARD) {   // Standard packet

      if (!(type&PKT_HDR_BITMASK_LOCAL)) { // Standard routed packet

        u32 dir = type&PKT_HDR_BITMASK_DIR;

        if (type&PKT_HDR_BITMASK_OVERRUN) {
          printk(KERN_ERR "(%s) Packet overrun reported on size %d packet\n", getDirName(type&0x7), len);
        }

        if (type&PKT_HDR_BITMASK_ERROR) {
          printk(KERN_ERR "(%s) Packet error reported on size %d packet\n", getDirName(type&0x7),len);
          DBGPRINT_HEX_DUMP(DBG_PKT_ERROR,
                            KERN_INFO, minor ? "<pru1: " : "<pru0: ",
                            DUMP_PREFIX_NONE, 16, 1,
                            bytes, len, true);
        }

        if (len > ITC_MAX_PACKET_SIZE) {
          printk(KERN_ERR "(%s) Truncating overlength (%d) packet\n",getDirName(type&0x7),len);
          len = ITC_MAX_PACKET_SIZE;
        }

        { /* Deliver to appropriate device */

          ITCPktDeviceState * pktdev;
          ITCPacketBuffer * ipb;
          bool urgent = type&PKT_HDR_BITMASK_MFMT;
          u32 index = urgent ? 1 : 0;
          ITCTrafficStats * t = getITCTrafficStatsFromDir(dir);

          t->mCounts[index].mPacketsReceived++;
          t->mCounts[index].mBytesReceived += len;

          pktdev = S.mPktDeviceState[index]; /* 0==/dev/itc/packets, 1==/dev/itc/mfm */

          BUG_ON(!pktdev);
          ipb = &pktdev->mUserIB;

          if (kfifo_avail(&ipb->mFIFO) < len) 
            printk(KERN_ERR "(%s) Inbound %s queue full, dropping %s len=%d packet\n",
                   getDirName(type&0x7),
                   ipb->mName,
                   urgent ? "priority" : "bulk",
                   len);
          else {
            kfifo_in(&ipb->mFIFO, data, len); 

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

      } else {                             // Standard local packet
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
        printk(KERN_ERR "(%s) Inbound queue full, dropping PRU%d len=%d packet\n",
               getDirName(type&0x7), minor, len);
      else {
        u32 copied = kfifo_in(&ipb->mFIFO, data, len);
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
}

static void initITCPacketBuffer(ITCPacketBuffer * ipb, const char * ipbname, bool routed, bool priority) {
  BUG_ON(!ipb);
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
  initITCPacketBuffer(&pktdev->mUserIB,"mUserIB",false,false);
  return pktdev;
}

static ITCPRUDeviceState * makeITCPRUDeviceState(struct device * dev,
                                                 int minor_to_create,
                                                 int * err_ret)
{
  ITCCharDeviceState* cdev = makeITCCharDeviceState(dev, sizeof(ITCPRUDeviceState), minor_to_create, err_ret);
  ITCPRUDeviceState* prudev = (ITCPRUDeviceState*) cdev;
  prudev->mRpmsgChannel = 0; /* caller inits later */
  initITCPacketBuffer(&prudev->mLocalIB,"mLocalIB",false,false);
  initITCPacketBuffer(&prudev->mPriorityOB,"mPriorityOB",true,true);
  initITCPacketBuffer(&prudev->mBulkOB,"mBulkOB",true,false);
  return prudev;
}


/*
 * driver probe function
 */

static int itc_pkt_probe(struct rpmsg_channel *rpmsg_chnl)
{
  int ret;
  ITCPRUDeviceState *prudevstate;
  int minor_obtained;

  printk(KERN_INFO "ZORG itc_pkt_probe dev=%p\n", &rpmsg_chnl->dev);

  dev_info(&rpmsg_chnl->dev, "chnl: 0x%x -> 0x%x\n", rpmsg_chnl->src,
           rpmsg_chnl->dst);

  minor_obtained = rpmsg_chnl->dst - 30;
  if (minor_obtained < 0 || minor_obtained > 1) {
    dev_err(&rpmsg_chnl->dev, "Failed : Unrecognized destination %d\n",
            rpmsg_chnl->dst);
    return -ENODEV;
  }

  /* If first minor, first open packet and mfm devices */
  if (S.mOpenPRUMinors == 0) {

    unsigned i;

    for (i = 0; i <= 1; ++i) {
      unsigned minor_to_create = i + PKT_MINOR_ITC;

      printk(KERN_INFO "ZROG making minor %d (on minor_obtained %d)\n", minor_to_create, minor_obtained);

      S.mPktDeviceState[i] = makeITCPktDeviceState(&rpmsg_chnl->dev, minor_to_create, &ret);

      printk(KERN_INFO "GROZ made minor %d=%p (err %d)SLORG\n", minor_to_create, &S.mPktDeviceState[i], ret);

      if (!S.mPktDeviceState[i])
        return ret;

    }
  }

  printk(KERN_INFO "GORZ minor_obtained %d\n",minor_obtained);

  BUG_ON(S.mPRUDeviceState[minor_obtained]);

  prudevstate = makeITCPRUDeviceState(&rpmsg_chnl->dev, minor_obtained, &ret);

  printk(KERN_INFO "BLURGE back with devstate=%p\n",prudevstate);

  if (!prudevstate)
    return ret;

  prudevstate->mRpmsgChannel = rpmsg_chnl;

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
  .class_attrs = itc_pkt_class_attrs,
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

  if (minor_obtained == 2)
    snprintf(devname,BUFSZ,"itc!packets");
  else if (minor_obtained == 3)
    snprintf(devname,BUFSZ,"itc!mfm");
  else
    snprintf(devname,BUFSZ,"itc!pru%d",minor_obtained);

  printk(KERN_INFO "ZERGIN: makeITCCharDeviceState(%p,%u,%d,%p) for %s\n", dev, struct_size, minor_obtained, err_ret, devname);

  cdevstate = devm_kzalloc(dev, struct_size, GFP_KERNEL);
  if (!cdevstate) {
    ret = -ENOMEM;
    goto fail_kzalloc;
  }

  strncpy(cdevstate->mName,devname,DBG_NAME_MAX_LENGTH);
  cdevstate->mDevt = MKDEV(MAJOR(S.mMajorDevt), minor_obtained);

  printk(KERN_INFO "INITTING /dev/%s with minor_obtained=%d (dev=%p)\n", devname, minor_obtained, dev);

  cdev_init(&cdevstate->mLinuxCdev, &itc_pkt_fops);
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

static void unmakeITCCharDeviceState(ITCCharDeviceState * cdevstate) {
  device_destroy(&itc_pkt_class_instance, cdevstate->mDevt);
  cdev_del(&cdevstate->mLinuxCdev);
}

static void unmakeITCPktDeviceState(ITCPktDeviceState * pktdevstate) {
  unmakePacketBuffer(&pktdevstate->mUserIB);
  unmakeITCCharDeviceState((ITCCharDeviceState *) pktdevstate);
}

static void unmakeITCPRUDeviceState(ITCPRUDeviceState * prudevstate) {
  BUG_ON(S.mOpenPRUMinors < 1);
  unmakePacketBuffer(&prudevstate->mLocalIB);
  unmakePacketBuffer(&prudevstate->mPriorityOB);
  unmakePacketBuffer(&prudevstate->mBulkOB);
  unmakeITCCharDeviceState((ITCCharDeviceState *) prudevstate);
  --S.mOpenPRUMinors;
}

static void itc_pkt_remove(struct rpmsg_channel *rpmsg_chnl) {
  ITCPRUDeviceState * prudevstate = dev_get_drvdata(&rpmsg_chnl->dev);

  unmakeITCPRUDeviceState(prudevstate);

  if (S.mOpenPRUMinors == 0) {
    int i;
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
  destroyITCModuleState(&S);

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

MODULE_VERSION("0.5");            ///< 0.5 for /dev/itc/mfm
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
