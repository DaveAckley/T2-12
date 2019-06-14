#ifndef ITC_PKT_H
#define ITC_PKT_H

#include <linux/kernel.h>
#include <linux/rpmsg.h>
#include <linux/slab.h>
#include <linux/fs.h>
#include <linux/init.h>
#include <linux/cdev.h>
#include <linux/module.h>
#include <linux/kfifo.h>
#include <linux/uaccess.h>
#include <linux/poll.h>

#include "pin_info_maps.h"
  
typedef enum packet_header_bits {
  PKT_HDR_BITMASK_STANDARD  = 0x80,
  PKT_HDR_BITMASK_LOCAL     = 0x40,
  PKT_HDR_BITMASK_MFMT      = 0x20,

  // Standard Routed bits
  PKT_HDR_BITMASK_OVERRUN   = 0x10,
  PKT_HDR_BITMASK_ERROR     = 0x08,
  PKT_HDR_BITMASK_DIR       = 0x07,

  // Standard Local bits
  PKT_HDR_BITMASK_LOCAL_TYPE= 0x1f
} PacketHeaderBits;

#define PRU_MINORS 2   /* low-level access to PRU0, PRU1*/
#define PKT_MINORS 2   /* processed access to itc, mfm */

#define MINOR_DEVICES (PRU_MINORS + PKT_MINORS) 
#define PRU_MINOR_PRU0 0
#define PRU_MINOR_PRU1 1

#define PKT_MINOR_ITC 2
#define PKT_MINOR_MFM 3

#define RPMSG_BUF_SIZE 512

/*Note RPMSG takes up to 500+ but the ITCs need the length to fit in a byte */
#define RPMSG_MAX_PACKET_SIZE (RPMSG_BUF_SIZE-sizeof(struct rpmsg_hdr))
#define ITC_MAX_PACKET_SIZE 255

#define KFIFO_SIZE (1<<12)   /* ITC packets are max 255.  Guarantee space for 16 (256*16 == 4,096 == 2**12) */

/* PRU special packets are expected to be smaller and rarer.  Give them 1KB each */
#define SPECIAL_KFIFO_SIZE (1<<10)

/* REC_1 for one byte record lengths is perfect for us.. */
typedef STRUCT_KFIFO_REC_1(KFIFO_SIZE) ITCPacketFIFO;
typedef STRUCT_KFIFO_REC_1(SPECIAL_KFIFO_SIZE) SpecialPacketFIFO;

typedef enum debug_flags {
  DBG_PKT_RCVD      = 0x00000001,
  DBG_PKT_SENT      = 0x00000002,
  DBG_PKT_ROUTE     = 0x00000004,
  DBG_PKT_ERROR     = 0x00000008,
} DebugFlags;

#define DBGIF(mask) if ((mask)&S.debugFlags)
#define DBGPRINTK(mask, printkargs...) do { DBGIF(mask) printk(printkargs); } while (0);
#define DBGPRINT_HEX_DUMP(mask, printhexdumpargs...) do { DBGIF(mask) print_hex_dump(printhexdumpargs); } while (0);

typedef struct {
  ITCPacketFIFO     mQueue;        /* a packet queue for some purpose */
  wait_queue_head_t mWaitQ;        /* for people waiting on this buffer */
  struct mutex      mLock;         /* lock for modifying this struct */
} ITCPacketBuffer;

typedef struct {             /* General char device state */
  bool mDeviceOpenedFlag;    /* true between .open and .close calls */
  struct cdev mLinuxCdev;    /* Linux character device state */
  dev_t mDevt;               /* Major:minor assigned to this device */
} ITCCharDevState;

/* per rpmsg-probed device -- in our case, per PRU */
typedef struct {
  ITCCharDevState mCDevState; /* char device state must be first! */

  struct rpmsg_channel *mRpmsgChannel; /* IO channel to PRU */
  struct device *mLinuxDev;            /* Ptr to linux device struct */

  ITCPacketBuffer mSpecialPB;  /* for special packet replies from PRU */
} ITCPRUDeviceState;

/* per 'processed' packet device - /dev/itc/{packets,mfm} */
typedef struct {
  ITCCharDevState mCDevState; /* char device state must be first! */
  struct device *mLinuxDev;     /* Ptr to linux device struct */

  ITCPacketBuffer   mInboundPB;  /* pkts from PRU awaiting delivery to userspace */
  ITCPacketBuffer   mOutboundPB; /* pkts from userspace awaiting rpmsg to PRU */

} ITCPktDeviceState;

/* per dirnum */
typedef struct {
  uint32_t dirNum;
  uint32_t bytesSent, bytesReceived;
  uint32_t packetsSent, packetsReceived;
  uint32_t packetSyncAnnouncements;
  uint32_t syncFailureAnnouncements;
  uint32_t timeoutAnnouncements;
} ITCTrafficStats;

/* 'global' state, so far as we can structify it */
typedef struct {
  DebugFlags        mDebugFlags;
  dev_t             mMajorDevT;     /* our dynamically-allocated major device number */

  int               mOpenPruMinors;/* how many of our minors have (ever?) been opened */

  uint32_t          itcEnabledStatus; /* dirnum -> packet enabled status one hex digit per */
  ITCTrafficStats   itcStats[ITC_DIR_COUNT]; /* statistics per ITC (0 and 4 unused in T2) */

  ITCPRUDeviceState * (mPRUDeviceState[PRU_MINORS]); /* ptrs to per-PRU device state */
  ITCPktDeviceState * (mPktDeviceState[PKT_MINORS]); /* ptrs to per-packet device state */
} ITCModuleState;

extern __printf(5,6) int send_msg_to_pru(unsigned prunum,
                                         unsigned wait,
                                         char * buf,
                                         unsigned bugsiz,
                                         const char * fmt, ...);

extern ITCDeviceState * make_itc_minor(struct device * dev,
                                       int minor_obtained,
                                       int * err_ret);

#endif /* ITC_PKT_H */
