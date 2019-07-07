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
#include <linux/kthread.h>         /* For thread functions */
#include <linux/delay.h>           /* For msleep functions */
#include <linux/random.h>          /* for prandom_u32_max() */
#include <linux/uaccess.h>
#include <linux/poll.h>
#include <linux/ctype.h>           /* for isprint, tolower */


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

typedef enum {
  DBG_PKT_RCVD      = 0x00000001,
  DBG_PKT_SENT      = 0x00000002,
  DBG_PKT_ROUTE     = 0x00000004,
  DBG_PKT_ERROR     = 0x00000008,
  DBG_TRACE_PARSE   = 0x00000010,
  DBG_TRACE_EXEC    = 0x00000020,
  DBG_TRACE_FULL    = 0x00000040,
} DebugFlags;

#define DBGP(mask) ((mask)&S.mDebugFlags)
#define DBGIF(mask) if (DBGP(mask))
#define DBGPRINTK(mask, printkargs...) do { DBGIF(mask) printk(printkargs); } while (0);
#define DBGPRINT_HEX_DUMP(mask, printhexdumpargs...) do { DBGIF(mask) print_hex_dump(printhexdumpargs); } while (0);

#define DBG_NAME_MAX_LENGTH 32
#define TRACE_MAX_LEN 4
typedef struct {
  u8 mActiveLength;
  u8 mMask[TRACE_MAX_LEN];
  u8 mValue[TRACE_MAX_LEN];
} TracePoint;

enum {
  BUFFERSET_U = 0,
  BUFFERSET_L,
  BUFFERSET_P,
  BUFFERSET_B
};

typedef struct {
  TracePoint mPattern;
  size_t mCount;
  u8 * mProgram;
  u8 * mCurrent;
  u8 mMinorSet;
  u8 mBufferSet;
} TracePointParser;

#define TRACEPOINT_PROGRAM_MAX_LEN 1024
typedef struct {
  u32 mLength;
  u8 mCode[TRACEPOINT_PROGRAM_MAX_LEN];
} TracePointProgram;

typedef struct {
  ITCPacketFIFO     mFIFO;   /* a packet fifo for some purpose */
  wait_queue_head_t mReaderQ;/* for readers waiting for fifo non-empty */
  wait_queue_head_t mWriterQ;/* for writers waiting for fifo non-full */
  struct mutex      mLock;   /* lock for modifying this struct */
  char mName[DBG_NAME_MAX_LENGTH];   /* debug name of buffer */
  u8 mMinor;                         /* minor of this buffer */
  u8 mBuffer;                        /* buffer code of this buffer */
  bool mRouted;              /* Packets in this buffer are routed */
  bool mPriority;            /* This is a priority buffer */
  TracePoint mTraceInsert;   /* What fifo additions to trace */
  TracePoint mTraceRemove;   /* What fifo removals to trace */
} ITCPacketBuffer;

typedef struct {             /* General char device state */
  struct cdev mLinuxCdev;    /* Linux character device state */
  struct device *mLinuxDev;  /* Ptr to linux device struct */
  dev_t mDevt;               /* Major:minor assigned to this device */
  bool mDeviceOpenedFlag;    /* true between .open and .close calls */
  char mName[DBG_NAME_MAX_LENGTH];   /* debug name of device */
} ITCCharDeviceState;

/* per rpmsg-probed device -- in our case, per PRU */
typedef struct {
  ITCCharDeviceState mCDevState; /* char device state must be first! */

  struct rpmsg_channel *mRpmsgChannel; /* IO channel to PRU */
  unsigned char mTempPacketBuffer[RPMSG_MAX_PACKET_SIZE]; /* Buffer for pkt transfer grr */
  ITCPacketBuffer mLocalIB;    /* for non-standard packet replies from PRU */
  ITCPacketBuffer mPriorityOB; /* urgent pkts from userspace awaiting rpmsg to PRU */
  ITCPacketBuffer mBulkOB;     /* background pkts from userspace awaiting rpmsg to PRU */
} ITCPRUDeviceState;

/* per 'processed' packet device - /dev/itc/{packets,mfm} */
typedef struct {
  ITCCharDeviceState mCDevState; /* char device state must be first! */
  ITCPacketBuffer mUserIB;  /* pkts from PRU awaiting delivery to userspace */
} ITCPktDeviceState;

typedef struct {
  uint32_t mBytesSent;
  uint32_t mBytesReceived;
  uint32_t mPacketsSent;
  uint32_t mPacketsReceived;
} ITCTrafficCounts;

/* per dirnum */
typedef struct {
  ITCTrafficCounts mCounts[2];  /* 0 == bulk, 1 == priority */
  uint32_t mDirNum;
  uint32_t mPacketSyncAnnouncements;
  uint32_t mSyncFailureAnnouncements;
  uint32_t mTimeoutAnnouncements;
} ITCTrafficStats;

/* 'global' state, so far as we can structify it */
typedef struct {
  DebugFlags        mDebugFlags;
  dev_t             mMajorDevt;     /* our dynamically-allocated major device number */

  int               mOpenPRUMinors;/* how many of our minors have (ever?) been opened */

  uint32_t          mItcEnabledStatus; /* dirnum -> packet enabled status one hex digit per */
  ITCTrafficStats   mItcStats[ITC_DIR_COUNT]; /* statistics per ITC (0 and 4 unused in T2) */

  ITCPRUDeviceState * (mPRUDeviceState[PRU_MINORS]); /* per-PRU-device state for minors 0,1 */
  ITCPktDeviceState * (mPktDeviceState[PKT_MINORS]); /* per-packet-device state for minors 2,3 */

  struct task_struct * mShipOBPktTask;     /* kthread to push packets to PRUs */
  wait_queue_head_t mOBWaitQueue;          /* wait queue for mShipOBPktTask */
} ITCModuleState;

#endif /* ITC_PKT_H */
