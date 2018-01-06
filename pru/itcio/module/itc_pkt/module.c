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

#include "module.h"
#include "SharedState.h"
#include <linux/dma-mapping.h>

/* define MORE_DEBUGGING to be more verbose and slow*/
#define MORE_DEBUGGING 1

#ifndef MORE_DEBUGGING
#define MORE_DEBUGGING 0
#endif

static ITCPacketDriverState S;

static int debugflags = 0;
module_param(debugflags, int, 0);
MODULE_PARM_DESC(debugflags, "Extra debugging flags; 0 for none");

static void initITCPacketDriverState(ITCPacketDriverState *s)
{
  init_waitqueue_head(&s->itcPacketWaitQ);
  mutex_init(&s->standardLock);
  s->packetPhysP = 0;
  s->packetVirtP = 0;
  s->open_pru_minors = 0;
  {
    unsigned i;
    for (i = 0; i < MINOR_DEVICES; ++i) s->dev_packet_state[i] = 0;
  }
#if MORE_DEBUGGING
   s->debugFlags = 0xf; // default some debugging on
#endif
   s->debugFlags |= debugflags;
}

static int initITCSharedPacketBuffers(ITCPacketDriverState *s)
{
  void *virtp;
  dma_addr_t dma = 0;
  size_t size = sizeof(struct SharedState);

  printk(KERN_INFO "itc_pkt: Allocating %dB coherent shared state\n", size);

  if (!s) return -EINVAL;
  if (s->packetPhysP || s->packetVirtP) return -EEXIST;

  printk(KERN_INFO "dma_alloc_coherent %u\n", size);
  virtp = dma_alloc_coherent(0, size, &dma, GFP_KERNEL);

  printk(KERN_INFO "gots virtp %p / physp 0x%08x OGLURB\n", virtp, dma);

  if (!virtp) {
    printk(KERN_WARNING "dma_alloc_coherent failed\n");
    return -EINVAL;
  }

  s->packetVirtP = (struct SharedState *) virtp;
  s->packetPhysP = dma;

  initSharedState(s->packetVirtP);

  return 0;
}

static void freeITCSharedPacketBuffers(ITCPacketDriverState *s)
{
  size_t size = sizeof(struct SharedState);

  printk(KERN_INFO "prefreesnrog\n");
  if (!s->packetVirtP || !s->packetPhysP) {
    printk(KERN_WARNING "freeITCSharedPacketBuffers without active alloc\n");
    return;
  }
  dma_free_coherent(0, size, s->packetVirtP, s->packetPhysP);

  s->packetVirtP = 0;
  s->packetPhysP = 0;

  printk(KERN_INFO "postdujrrn\n");
}

int ship_packet_to_pru(unsigned prunum, unsigned wait, char * pkt, unsigned pktlen)
{
  struct SharedStatePerPru * sspp;
  struct PacketBuffer * dpb;
  ITCDeviceState *devstate;
  int ret;

  BUG_ON(prunum > 1);

  devstate = S.dev_packet_state[prunum];
  BUG_ON(!devstate);
  BUG_ON(!devstate->rpmsg_dev);

  if (pktlen >= ITC_MAX_PACKET_SIZE) {
    printk(KERN_WARNING "shippackettopru overlength (%d) packet (type='%c') truncated\n",
           pktlen, pkt[0]);
    pktlen = ITC_MAX_PACKET_SIZE - 1;
  }
  
  sspp = &S.packetVirtP->pruState[prunum];
  dpb = PacketBufferFromPacketBufferStorageInline(sspp->downbound);

  if (mutex_lock_interruptible(&devstate->specialLock))
    return -ERESTARTSYS;

  //////////&devstate->specialLock HELD//////////
  DBGPRINT_HEX_DUMP(DBG_PKT_SENT,
                    KERN_INFO, prunum ? ">pru1: " : ">pru0: ",
                    DUMP_PREFIX_NONE, 16, 1,
                    pkt, pktlen, true);

  ret = pbWritePacketIfPossible(dpb, pkt, pktlen);
  if (ret < 0) printk(KERN_ERR "special packet send failed (%d)\n", ret);
  else if (wait) {
    struct PacketBuffer * upb = PacketBufferFromPacketBufferStorageInline(sspp->upbound);
    printk(KERN_INFO "shippackettpru starting to wait\n");
    while (pbIsEmptyInline(upb)) {
      printk(KERN_INFO "shippackettopru while wait\n");
      if (wait_event_interruptible(devstate->specialWaitQ, !pbIsEmptyInline(upb))) {
        ret = -ERESTARTSYS;
        break;
      }
    }

    printk(KERN_INFO "shippackettopru while done %d\n", ret);

    if (ret == 0) {
      /* Note that if you are waiting for a response, it must fit in
         your sending buffer or this will fail! */
      printk(KERN_INFO "shippacketto reading\n");
      ret = pbReadPacketIfPossible(upb, pkt, pktlen);
      printk(KERN_INFO "shippacketpru read %d\n",ret);
      if (ret < 0) {
        printk(KERN_ERR "special packet response read failed (%d)\n", ret);
      }
    }
  }
  printk(KERN_INFO "shippacketpru unlocking, ret %d, wait %d\n", ret, wait);
  mutex_unlock(&devstate->specialLock);
  //////////&devstate->specialLock RELEASED//////////

  return ret;
}

__printf(5,6) int send_msg_to_pru(unsigned prunum,
                                  unsigned wait,
                                  char * buf,
                                  unsigned bufsiz,
                                  const char * fmt, ...)
{
  unsigned len;
  va_list args;

  va_start(args, fmt);
  len = vsnprintf(buf, bufsiz, fmt, args);
  va_end(args);

  return ship_packet_to_pru(prunum, wait, buf, len);
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

static ssize_t itc_pkt_class_read_debug(struct class *c,
                                        struct class_attribute *attr,
                                        char *buf)
{
  sprintf(buf,"%x\n",S.debugFlags);
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
    S.debugFlags = tmpdbg;
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

  /*
  printk(KERN_INFO "HI CLASS STORE %p ATTR %p (pru=%u,prudir=%u,bit=%u)(val=%u)\n",
         c, attr,
         pru, prudir, bit,
         val);
  */

  /* We wait for a return just to get it out of the buffer*/
  ret = send_msg_to_pru(pru, 1, msg, RPMSG_MAX_PACKET_SIZE, "B%c%c-", bit, val);
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

  /*
  printk(KERN_INFO "HI FROM CLASS %p ATTR %p (pru=%u,prudir=%u,bit=%u)\n",
         c, attr,
         pru, prudir, bit);
  */

  ret = send_msg_to_pru(pru, 1, msg, RPMSG_MAX_PACKET_SIZE, "Rxxxx-");
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
  ITCDeviceState * devstate;
  devstate = container_of(inode->i_cdev, ITCDeviceState, cdev);

#if MORE_DEBUGGING
  printk(KERN_INFO "itc_pkt_open %d:%d\n",
         MAJOR(devstate->devt),
         MINOR(devstate->devt));
#endif

  if (!devstate->dev_lock) {
    devstate->dev_lock = true;
    filp->private_data = devstate;
    ret = 0;
  }

  if (ret)
    dev_err(devstate->dev, "Device already open\n");

  return ret;
}

/** @brief The callback for when the device is closed/released by
 *  the userspace program
 *  @param inodep A pointer to an inode object (defined in linux/fs.h)
 *  @param filep A pointer to a file object (defined in linux/fs.h)
 */
static int itc_pkt_release(struct inode *inode, struct file *filp)
{
  ITCDeviceState *devstate;

  devstate = container_of(inode->i_cdev, ITCDeviceState, cdev);
#if MORE_DEBUGGING
  printk(KERN_INFO "itc_pkt_release %d:%d\n",
         MAJOR(devstate->devt),
         MINOR(devstate->devt));
#endif

  devstate->dev_lock = false;

  return 0;
}

static int routeStandardPacket(struct SharedStateSelector * sss, const unsigned char * buf, size_t len)
{
  if (len == 0) return -EINVAL;
  if ((buf[0] & 0x80) == 0) return -ENXIO; /* only standard packets can be routed */
  switch (buf[0] & 0x7) {
  default: return -ENODEV;
#define XX(dir)                                         \
    case ITC_DIR_TO_DIR_NUM(dir):                       \
    sss->pru = ITC_DIR_TO_PRU(dir);                     \
    sss->prudir = ITC_DIR_TO_PRU(dir);                  \
    break;
FOR_XX_IN_ITC_ALL_DIR
#undef XX
  }
  return 0;
}

        
static void processBufferKick(struct SharedStateSelector* sss)
{
  static unsigned kicks = 0;
  struct PacketBuffer * pb = getPacketBufferIfAnyInline(S.packetVirtP, sss);
  unsigned char selbuf[7];
  sharedStateSelectorCode(sss,selbuf);
  selbuf[4] = ':';
  selbuf[5] = ' ';
  selbuf[6] = '\0';

  if ((++kicks&0xfff)==0)
    printk(KERN_INFO "%sTotal kicks now %u\n", selbuf, kicks);

  if (!pb) {
    printk(KERN_ERR "%sNo packet buffer found for kick %d%d%d%d\n",
           selbuf, sss->pru,sss->prudir,sss->inbound,sss->bulk);
  } else {
    unsigned char buff[256];
    int ret;
    
    while ((ret = pbReadPacketIfPossible(pb,buff,256)) > 0) {
      DBGPRINT_HEX_DUMP(DBG_PKT_RCVD,
                        KERN_INFO, selbuf,
                        DUMP_PREFIX_NONE, 16, 1,
                        buff, ret, true);
    }
  }
}

/** @brief This callback used when data is being written to the device
 *  from user space.  Note that although rpmsg allows messages over
 *  500 bytes long, so that's the limit for talking to a local PRU,
 *  intertile packets are limited to at most 255 bytes.  Here, that
 *  limit is enforced only for minor 2 (/dev/itc/packets) because
 *  packets sent there are necessarily routable intertile.
 *
 *  @param filp A pointer to a file object
 *  @param buf The buffer to that contains the data to write to the device
 *  @param count The number of bytes to write from buf
 *  @param offset The offset if required
 */

static ssize_t itc_pkt_write(struct file *filp,
                             const char __user *buf,
                             size_t count, loff_t *offset)
{
  int ret;
  static unsigned char driver_buf[RPMSG_BUF_SIZE];
  ITCDeviceState *devstate;
  unsigned origminor;

  devstate = filp->private_data;

  if (count > RPMSG_MAX_PACKET_SIZE) {
    dev_err(devstate->dev, "Data length (%d) exceeds rpmsg buffer size", count);
    return -EINVAL;
  }

  if (copy_from_user(driver_buf, buf, count)) {
    dev_err(devstate->dev, "Failed to copy data");
    return -EFAULT;
  }

  origminor = MINOR(devstate->devt);

  if (origminor == 2) {
    struct SharedStateSelector sss;
    int newMinor, ret;

    initSharedStateSelector(&sss);
    ret = routeStandardPacket(&sss, driver_buf, count);

    if (ret < 0)
      return ret;          // bad routing

    newMinor = sss.pru;

    if (count > ITC_MAX_PACKET_SIZE) {
      dev_err(devstate->dev, "Routable packet size (%d) exceeds ITC length max (255)", count);
      return -EINVAL;
    }


    if (newMinor < 2) {
      DBGPRINTK(DBG_PKT_ROUTE,
                KERN_INFO "Routing '%x'+%d packet to PRU%d\n",driver_buf[0],count,newMinor);
      devstate = S.dev_packet_state[newMinor];
      BUG_ON(!devstate);
    }

    {
      struct PacketBuffer * pb = getPacketBufferIfAny(S.packetVirtP, &sss);
      if (!pb) {
        dev_err(devstate->dev, "No FOB packet buffer found?");
        return -EINVAL;
      }
      ret = pbWritePacketIfPossible(pb, driver_buf, count);
      if (ret < 0) {
        dev_err(devstate->dev,
                "FOB packet transmission failed %d\n",ret);
        return ret;
      }
    }
    return count;
  }

  /*Here for packets explicitly to minor/pru [01]  */

  {
    ret = ship_packet_to_pru(origminor, 0, driver_buf, count);
    printk(KERN_INFO "DOWNBOUND SPECIAL (%s) GOT %d\n",driver_buf,ret);
    if (ret) {
      dev_err(devstate->dev,
              "Shared state transmission failed %d\n",ret);
      return -EFAULT;
    }
  }

#if MORE_DEBUGGING
  dev_info(devstate->dev,
           (driver_buf[0]&0x80)?
             "Sending length %d type 0x%02x packet" :
             "Sending length %d type '%c' packet",
           count,
           driver_buf[0]);
#endif

  return count;
}

static ssize_t itc_pkt_read(struct file *file, char __user *buf,
                            size_t count, loff_t *ppos)
{
  int ret = 0;

  ITCDeviceState *devstate = file->private_data;
  int minor = MINOR(devstate->devt);
  //  int major = MAJOR(devstate->devt);
  //  printk(KERN_INFO "read file * = %p, %d:%d\n", file, major, minor);

  switch (minor) {
  case 0:
  case 1: {
    struct SharedStatePerPru * sspp = &S.packetVirtP->pruState[minor];
    struct PacketBuffer * upb = PacketBufferFromPacketBufferStorageInline(sspp->upbound);

    if (mutex_lock_interruptible(&devstate->specialLock))
      return -ERESTARTSYS;
    printk(KERN_INFO "PREWHILE\n");
    while (pbIsEmptyInline(upb)) {
      printk(KERN_INFO "INWHILE1\n");
      if (file->f_flags & O_NONBLOCK) {
        printk(KERN_INFO "INWHILE2\n");
        ret = -EAGAIN;
        break;
      }
      printk(KERN_INFO "INWHILE3\n");
      if (wait_event_interruptible(devstate->specialWaitQ, !pbIsEmptyInline(upb))) {
        printk(KERN_INFO "INWHILE4\n");
        ret = -ERESTARTSYS;
        break;
      }
    }
    printk(KERN_INFO "POSTWHILE (%d)\n", ret);

    if (ret == 0)
      ret = pbReadPacketIfPossibleToUser(upb, buf, count);

    printk(KERN_INFO "POSTREAD (%d)\n", ret);

    mutex_unlock(&devstate->specialLock);
    break;
  }

  case 2: {
    printk(KERN_ERR "SUMMON THE REIMPLEMENTOR FOR SPECIALS ON PRUDEVS\n");
    return -EINVAL;
#if 0
    ITCPacketFIFO * devfifo = &S.itcPacketKfifo;

    if (mutex_lock_interruptible(&S.standardLock))
      return -ERESTARTSYS;

    while (kfifo_is_empty(devfifo)) {
      if (file->f_flags & O_NONBLOCK) {
        ret = -EAGAIN;
        break;
      }
      if (wait_event_interruptible(S.itcPacketWaitQ, !kfifo_is_empty(devfifo))) {
        ret = -ERESTARTSYS;
        break;
      }

    }
    if (ret == 0)
      ret = kfifo_to_user(devfifo, buf, count, &copied);

    mutex_unlock(&S.standardLock);

    break;
#endif
  }

  default: BUG_ON(1);
  }

  return ret;
}


static const struct file_operations itc_pkt_fops = {
  .owner= THIS_MODULE,
  .open	= itc_pkt_open,
  .read = itc_pkt_read,
  .write= itc_pkt_write,
  .release= itc_pkt_release,
};


static void itc_pkt_cb(struct rpmsg_channel *rpmsg_dev,
                       void *data , int len , void *priv,
                       u32 src )
{
  ITCDeviceState * devstate = dev_get_drvdata(&rpmsg_dev->dev);
  int minor = MINOR(devstate->devt);

  //  printk(KERN_INFO "Received %d from %d\n",len, minor);

  if (len > 0) {
    int wake = -1;
    u8 * d = (u8*) data;
    u8 type =  d[0];

    if (type >= 2)
      DBGPRINT_HEX_DUMP(DBG_PKT_RCVD,
                        KERN_INFO, minor ? "<pru1: " : "<pru0: ",
                        DUMP_PREFIX_NONE, 16, 1,
                        data, len, true);


    // ITC data if first byte MSB set
    if (type&0x80) {
      if (type&0x10) {
        printk(KERN_ERR "Packet overrun reported on size %d packet\n",len);
      }
      if (type&0x08) {
        printk(KERN_ERR "Packet error reported on size %d packet\n",len);
      }
      if (len > ITC_MAX_PACKET_SIZE) {
        printk(KERN_ERR "Truncating overlength (%d) packet\n",len);
        len = ITC_MAX_PACKET_SIZE;
      }
    printk(KERN_ERR "SUMMON THE REIMPLEMENTOR\n");
#if 0
      kfifo_in(&S.itcPacketKfifo, data, len);
#endif
      wake_up_interruptible(&S.itcPacketWaitQ);
    } else {
      if (type<2) { // Then it's a shared state buffer kick from PRU(type)

        if (len != 4) {
          printk(KERN_ERR "Length %d buffer kick received, ignored\n",len);
        } else {
          processBufferKick((struct SharedStateSelector*) data);
        }
      } else {
        if (minor == 0) {
          wake = 0;
        } else if (minor == 1) {
          wake = 1;
        }
      }
    }
    if (wake >= 0) {
      wake_up_interruptible(&S.dev_packet_state[wake]->specialWaitQ);
    }
  }
}

/*
 * driver probe function
 */

static int itc_pkt_probe(struct rpmsg_channel *rpmsg_dev)
{
  int ret;
  ITCDeviceState *devstate;
  int minor_obtained;

  printk(KERN_INFO "ZORG itc_pkt_probe dev=%p\n",&rpmsg_dev->dev);

  dev_info(&rpmsg_dev->dev, "chnl: 0x%x -> 0x%x\n", rpmsg_dev->src,
           rpmsg_dev->dst);

  minor_obtained = rpmsg_dev->dst - 30;
  if (minor_obtained < 0 || minor_obtained > 1) {
    dev_err(&rpmsg_dev->dev, "Failed : Unrecognized destination %d\n",
            rpmsg_dev->dst);
    return -ENODEV;
  }

  /* If first minor, first open packet device*/
  if (S.open_pru_minors == 0) {

    BUG_ON(minor_obtained == 2);

    S.dev_packet_state[2] = make_itc_minor(&rpmsg_dev->dev, 2, &ret);

    printk(KERN_INFO "GROZ made minor 2=%p SLORG\n",S.dev_packet_state);

    if (!S.dev_packet_state[2])
      return ret;

    S.dev_packet_state[2]->rpmsg_dev = 0;
    ++S.open_pru_minors;
  }

  BUG_ON(S.dev_packet_state[minor_obtained]);

  devstate = make_itc_minor(&rpmsg_dev->dev, minor_obtained, &ret);

  printk(KERN_INFO "BLURGE back with devstate=%p\n",devstate);

  if (!devstate)
    return ret;

  S.dev_packet_state[minor_obtained] = devstate;

  devstate->rpmsg_dev = rpmsg_dev;
  ++S.open_pru_minors;

  /* send initial '@' packet via rpmsg to give PRU src & dst info, plus the shared space physaddr */
  {
    char buf[32];
    printk(KERN_INFO "BLURGE buf=%p\n",buf);
    snprintf(buf,32,"@%08x!",S.packetPhysP);
    ret = rpmsg_send(devstate->rpmsg_dev, (void *)buf, strlen(buf));
    if (ret) {
      dev_err(devstate->dev,
              "Transmission on rpmsg bus failed %d\n",ret);
      return -EFAULT;
    }

    printk(KERN_INFO "RECTOBLURGE sent buf='%s'\n",buf);
  }

  if (ret) {
    dev_err(devstate->dev, "Opening transmission on rpmsg bus failed %d\n",ret);
    ret = PTR_ERR(devstate->dev);
    cdev_del(&devstate->cdev);
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

ITCDeviceState * make_itc_minor(struct device * dev,
                                int minor_obtained,
                                int * err_ret)
{
  ITCDeviceState * devstate;
  enum { BUFSZ = 16 };
  char devname[BUFSZ];
  int ret;

  BUG_ON(!err_ret);

  if (minor_obtained == 2)
    snprintf(devname,BUFSZ,"itc!packets");
  else
    snprintf(devname,BUFSZ,"itc!pru%d",minor_obtained);

  devstate = devm_kzalloc(dev, sizeof(ITCDeviceState), GFP_KERNEL);
  if (!devstate) {
    ret = -ENOMEM;
    goto fail_kzalloc;
  }

  /* Clearly I don't get mutex_init.  It uses a static local
     supposedly to associate a 'unique' key with each mutex.  But if
     mutex_init is called in a loop (as here, implicitly), then we'll
     only get one key for all the mutexes, right?

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

        For example a lock in the inode struct is one class, while
        each inode has its own instantiation of that lock class.

     which makes it sound like of course I should have just one class
     for my pitiful little three lock instances.  But on the other
     hand lockdep-design also says this:

        The same lock-class must not be acquired twice, because this
        could lead to lock recursion deadlocks.

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

  mutex_init(&devstate->specialLock);
  init_waitqueue_head(&devstate->specialWaitQ);

  devstate->devt = MKDEV(MAJOR(S.major_devt), minor_obtained);

  printk(KERN_INFO "INITTING /dev/%s\n", devname);

  cdev_init(&devstate->cdev, &itc_pkt_fops);
  devstate->cdev.owner = THIS_MODULE;
  ret = cdev_add(&devstate->cdev, devstate->devt,1);

  if (ret) {
    dev_err(dev, "Unable to init cdev\n");
    goto fail_cdev_init;
  }

  devstate->dev = device_create(&itc_pkt_class_instance,
                                dev,
                                devstate->devt, NULL,
                                devname);

  if (IS_ERR(devstate->dev)) {
    dev_err(dev, "Failed to create device file entries\n");
    ret = PTR_ERR(devstate->dev);
    goto fail_device_create;
  }

  dev_set_drvdata(dev, devstate);
  dev_info(dev, "pru itc packet device ready at /dev/%s",devname);

  return devstate;

 fail_device_create:
  cdev_del(&devstate->cdev);

 fail_cdev_init:

 fail_kzalloc:
  *err_ret = ret;
  return 0;
}

static void itc_pkt_remove(struct rpmsg_channel *rpmsg_dev) {
  ITCDeviceState *devstate;

  devstate = dev_get_drvdata(&rpmsg_dev->dev);
  mutex_destroy(&devstate->specialLock);
  device_destroy(&itc_pkt_class_instance, devstate->devt);
  cdev_del(&devstate->cdev);
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

  initITCPacketDriverState(&S);

  ret = initITCSharedPacketBuffers(&S);
  if (ret) {
    pr_err("Failed to allocate shared packet buffers, error = %d", ret);
    goto fail_init_shared_buffers;
  }

  ret = class_register(&itc_pkt_class_instance);
  if (ret) {
    pr_err("Failed to register class\n");
    goto fail_class_register;
  }

  /*  itc_pkt_class_instance.dev_groups = itc_pkt_groups;   */

  ret = alloc_chrdev_region(&S.major_devt, 0,
                            MINOR_DEVICES, "itc_pkt");
  if (ret) {
    pr_err("Failed to allocate chrdev region\n");
    goto fail_alloc_chrdev_region;
  }

  ret = register_rpmsg_driver(&itc_pkt_driver);
  if (ret) {
    pr_err("Failed to register the driver on rpmsg bus");
    goto fail_register_rpmsg_driver;
  }

  return 0;

 fail_register_rpmsg_driver:
  unregister_chrdev_region(S.major_devt,
                           MINOR_DEVICES);
 fail_alloc_chrdev_region:
  class_unregister(&itc_pkt_class_instance);

 fail_class_register:
  freeITCSharedPacketBuffers(&S);

 fail_init_shared_buffers:
  return ret;
}


static void __exit itc_pkt_exit (void)
{
  {
    /*Try to halt the prus before bailing*/
    char buf[10];
    send_msg_to_pru(0, 0, buf, 10, "\177!");
    send_msg_to_pru(1, 0, buf, 10, "\177!");
  }

  if (S.dev_packet_state[2]) { /* [0] and [1] handled automatically, right? */
    device_destroy(&itc_pkt_class_instance, S.dev_packet_state[2]->devt);
  }

  freeITCSharedPacketBuffers(&S);

  unregister_rpmsg_driver(&itc_pkt_driver);
  class_unregister(&itc_pkt_class_instance);
  unregister_chrdev_region(S.major_devt,
                           MINOR_DEVICES);
}

module_init(itc_pkt_init);
module_exit(itc_pkt_exit);

MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("Dave Ackley <ackley@ackleyshack.com>");
MODULE_DESCRIPTION("T2 intertile packet communications subsystem");  ///< modinfo description

MODULE_VERSION("0.5");          ///< 0.5 for using shared memory
/// 0.4 for general internal renaming and reorg (201801031340)
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
