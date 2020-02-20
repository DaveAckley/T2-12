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

#include "rpmsg_t2_local.h"       /* XXX HOW ARE YOU SUPPOSED TO GET struct rpmsg?? */
#include "itcmfm.h"               /* For ITCLevelState_ops & assoc */

#include "dirdatamacro.h"         /* For DIR6_ET, DIR6_COUNT, etc */

#define ADD_PKT_EVENT(event)                                              \
  do {                                                                    \
   if (kfifo_avail(&(S.mEvtDeviceState[0]->mPktEvents.mEvents)) >= sizeof(ITCPktEvent)) \
     addPktEvent(&(S.mEvtDeviceState[0]->mPktEvents),(event));          \
  } while(0)   

#define ADD_ITC_EVENT(event)                                              \
  do {                                                                    \
   if (kfifo_avail(&(S.mEvtDeviceState[1]->mPktEvents.mEvents)) >= sizeof(ITCPktEvent)) \
     addPktEvent(&(S.mEvtDeviceState[1]->mPktEvents),(event));          \
  } while(0)   

#define ADD_PKT_EVENT_IRQ(event)                                          \
  do {                                                                     \
    if (kfifo_avail(&(S.mEvtDeviceState[0]->mPktEvents.mEvents)) >= sizeof(ITCPktEvent)) { \
      unsigned long flags;                                                 \
      local_irq_save(flags);                                               \
      addPktEvent(&(S.mEvtDeviceState[0]->mPktEvents),(event));         \
      local_irq_restore(flags);                                            \
    }                                                                      \
  } while(0)

#define ADD_ITC_EVENT_IRQ(event)                                          \
  do {                                                                     \
    if (kfifo_avail(&(S.mEvtDeviceState[1]->mPktEvents.mEvents)) >= sizeof(ITCPktEvent)) { \
      unsigned long flags;                                                 \
      local_irq_save(flags);                                               \
      addPktEvent(&(S.mEvtDeviceState[1]->mPktEvents),(event));         \
      local_irq_restore(flags);                                            \
    }                                                                      \
  } while(0)

#if 0
/* DIR6 definitions based on T2-12/lkms/itc//dirdatamacro.h, BUT ARE
   DEFINED HERE SEPARATELY.  

   'dir8' definitions (e.g., 'ITC_DIR's) are defined in pin_info.maps
 */
#define DIR6_ET 0
#define DIR6_SE 1
#define DIR6_SW 2
#define DIR6_WT 3
#define DIR6_NW 4
#define DIR6_NE 5
#define DIR6_COUNT 6
#endif

const char * getDir8Name(u8 dir8) ;

typedef enum packet_header_bits {
  PKT_HDR_BITMASK_STANDARD  = 0x80,
  PKT_HDR_BITMASK_LOCAL     = 0x40,
  PKT_HDR_BITMASK_URGENT    = 0x20,

  // Standard Routed bits
  PKT_HDR_BITMASK_OVERRUN   = 0x10,
  PKT_HDR_BITMASK_ERROR     = 0x08,
  PKT_HDR_BITMASK_DIR       = 0x07,

  // Standard Local bits
  PKT_HDR_BITMASK_LOCAL_TYPE= 0x1f
} PacketHeaderBits;

typedef enum packet_header_byte1_bits {
  PKT_HDR_BYTE1_BITMASK_MFM  = 0x80,      /* MFM traffic (rather than flash) */
  PKT_HDR_BYTE1_BITMASK_KITC = 0x40,      /* Kernel ITC traffic (rather than userspace) */
} PacketHeaderByte1Bits;

/////////TRACING SUPPORT

#define PKT_EVENT_KFIFO_SIZE (1<<11)   /* Guarantee space for 2K ITCPktEvents (8KB total == sizeof(ITCPktEvent)*2048) */
typedef STRUCT_KFIFO(ITCPktEvent, PKT_EVENT_KFIFO_SIZE) ITCPktEventFIFO;

typedef struct itcpkteventstate {
  ITCPktEventFIFO mEvents;
  u64 mStartTime;
  u8 mShiftDistance;
  struct mutex mPktEventReadMutex;	///< For read ops on kfifo
} ITCPktEventState;

/*WARNING: IF INTERRUPT HANDLERS ARE IN USE (which they are evidently
  NOT in itcpkt), THEN THIS MUST BE CALLED ONLY AT INTERRUPT LEVEL OR
  WITH INTERRUPTS DISABLED */
extern void addPktEvent(ITCPktEventState* pes, u32 event) ;

#define PRU_MINORS 2   /* low-level access to PRU0, PRU1*/
#define PKT_MINORS 2   /* processed access to itc, mfm */
#define EVT_MINORS 2   /* access to pktevt, itcevt state */
#define MFM_MINORS DIR6_COUNT   /* demuxed per-itc mfm packets */

#define MINOR_DEVICES (PRU_MINORS + PKT_MINORS + EVT_MINORS + MFM_MINORS) 
#define PRU_MINOR_PRU0 0
#define PRU_MINOR_PRU1 1

#define PKT_MINOR_BULK 2
#define PKT_MINOR_FLASH 3

#define PKT_MINOR_EVT 4
#define PKT_MINOR_ITC_EVT 5

#define PKT_MINOR_MFM_BASE 6

#define PKT_MINOR_MFM_ET (PKT_MINOR_MFM_BASE+DIR6_ET) /*  6 */
#define PKT_MINOR_MFM_SE (PKT_MINOR_MFM_BASE+DIR6_SE) /*  7 */
#define PKT_MINOR_MFM_SW (PKT_MINOR_MFM_BASE+DIR6_SW) /*  8 */
#define PKT_MINOR_MFM_WT (PKT_MINOR_MFM_BASE+DIR6_WT) /*  9 */
#define PKT_MINOR_MFM_NW (PKT_MINOR_MFM_BASE+DIR6_NW) /*  10 */
#define PKT_MINOR_MFM_NE (PKT_MINOR_MFM_BASE+DIR6_NE) /*  11 */

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
  DBG_PKT_DROPS     = 0x00000010,
  //0x020..0x80 rsrvd
  DBG_MISC100       = 0x00000100,
  DBG_MISC200       = 0x00000200,
  DBG_LVL_PIO       = 0x00000400,   /*level packet IO*/
  DBG_LVL_LSC       = 0x00000800,   /*level stage change*/
  //0x0400..0x800 rsrvd
  DBG_TRACE_PARSE   = 0x00001000,
  DBG_TRACE_EXEC    = 0x00002000,
  DBG_TRACE_FULL    = 0x00004000,
} DebugFlags;

#define DBGP(mask) ((mask)&S.mDebugFlags)
#define DBGIF(mask) if (DBGP(mask))
#define DBGPRINTK(mask, printkargs...) do { DBGIF(mask) printk(printkargs); } while (0)
#define DBGPRINT_HEX_DUMP(mask, printhexdumpargs...) do { DBGIF(mask) print_hex_dump(printhexdumpargs); } while (0)

#define DBG_NAME_MAX_LENGTH 32
#define TRACE_MAX_LEN 4
typedef struct {  /** 'struct tracepoint' already declared by linux/tracepoint-defs.h */
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

typedef struct tracepointparser {
  TracePoint mPattern;
  size_t mCount;
  u8 * mProgram;
  u8 * mCurrent;
  u8 mMinorSet;
  u8 mBufferSet;
} TracePointParser;

#define TRACEPOINT_PROGRAM_MAX_LEN 1024
typedef struct tracepointprogram {
  u32 mLength;
  u8 mCode[TRACEPOINT_PROGRAM_MAX_LEN];
} TracePointProgram;

typedef struct itcpacketbuffer {
  ITCPacketFIFO     mFIFO;   /* a packet fifo for some purpose */
  wait_queue_head_t mReaderQ;/* for readers waiting for fifo non-empty */
  wait_queue_head_t mWriterQ;/* for writers waiting for fifo non-full */
  struct mutex      mLock;   /* lock for modifying this struct */
  char mName[DBG_NAME_MAX_LENGTH];   /* debug name of buffer */
  u8 mMinor;                         /* minor of this buffer */
  u8 mBuffer;                        /* buffer code of this buffer */
  bool mRouted;              /* Packets in this outbound buffer are routed */
  bool mPriority;            /* This is a priority outbound buffer */
  TracePoint mTraceInsert;   /* What fifo additions to trace */
  TracePoint mTraceRemove;   /* What fifo removals to trace */
} ITCPacketBuffer;

typedef struct itcchardevicestate {             /* General char device state */
  struct cdev mLinuxCdev;    /* Linux character device state */
  struct device *mLinuxDev;  /* Ptr to linux device struct */
  dev_t mDevt;               /* Major:minor assigned to this device */
  bool mDeviceOpenedFlag;    /* true between .open and .close calls */
  char mName[DBG_NAME_MAX_LENGTH];   /* debug name of device */
} ITCCharDeviceState;

/* per rpmsg-probed device -- in our case, per PRU */
typedef struct itcprudevicestate {
  ITCCharDeviceState mCDevState; /* char device state must be first! */

  struct rpmsg_device *mRpmsgDevice; /* IO channel to PRU */
  unsigned char mTempPacketBuffer[RPMSG_MAX_PACKET_SIZE]; /* Buffer for pkt transfer grr */
  ITCPacketBuffer mLocalIB;    /* for non-standard packet replies from PRU */
  ITCPacketBuffer mPriorityOB; /* urgent pkts from userspace awaiting rpmsg to PRU */
  ITCPacketBuffer mBulkOB;     /* background pkts from userspace awaiting rpmsg to PRU */
} ITCPRUDeviceState;

/* per 'event' device - /dev/itc/pktevt, /dev/itc/itcevt */
typedef struct itcevtdevicestate {
  ITCCharDeviceState mCDevState; /* char device state must be first! */
  ITCPktEventState mPktEvents;  /* packet events state */
} ITCEvtDeviceState;

/* per 'processed' packet device - /dev/itc/{packets,mfm} */
typedef struct itcpktdevicestate {
  ITCCharDeviceState mCDevState; /* char device state must be first! */
  ITCPacketBuffer mUserIB;  /* pkts from PRU awaiting delivery to userspace */
} ITCPktDeviceState;

/* per 'mfm itc' device - currently /dev/itc/bydir/{ET,SE,SW,WT,NW,NE} */
typedef struct itcmfmdevicestate {
  ITCPktDeviceState mPktDevState;/* pkt device state must be first! */
  bool mStale;                   /* set on write to mfzid, cleared on open */
  u8 mDir6;                      /* implied by minor but for convenience */
  ITCLevelState mLevelState;
} ITCMFMDeviceState;

typedef struct itctrafficcounts {
  uint32_t mBytesSent;
  uint32_t mBytesReceived;
  uint32_t mPacketsSent;
  uint32_t mPacketsReceived;
} ITCTrafficCounts;

typedef enum trafficcounttypes {
  TRAFFIC_BULK,
  TRAFFIC_URGENT,
  TRAFFIC_COUNT_TYPES
} TrafficCountTypes;

/* per dirnum */
typedef struct itctrafficstats {
  ITCTrafficCounts mCounts[TRAFFIC_COUNT_TYPES];
  uint32_t mDirNum;
  uint32_t mPacketSyncAnnouncements;
  uint32_t mSyncFailureAnnouncements;
  uint32_t mTimeoutAnnouncements;
} ITCTrafficStats;

/* struct for kthread since now we're having two.. */
typedef struct itckthreadstate {
  struct task_struct * mThreadTask; /* kthread */
  wait_queue_head_t mWaitQueue;     /* wait queue for the thread */
  ITCIterator mDir6Iterator;        /* provide a per-thread iterator */
} ITCKThreadState;

/* 'global' state, so far as we can structify it */
typedef struct itcmodulestate {
  DebugFlags        mDebugFlags;
  dev_t             mMajorDevt;     /* our dynamically-allocated major device number */

  int               mOpenPRUMinors;/* how many of our minors have (ever?) been opened */

  uint32_t          mItcEnabledStatus; /* dirnum -> packet enabled status one hex digit per */
  ITCTrafficStats   mItcStats[DIR8_COUNT]; /* statistics per ITC (0 and 4 unused in T2) */
  MFMTileState      mMFMTileState;     /* info about userspace mfm config */

  ITCPRUDeviceState * (mPRUDeviceState[PRU_MINORS]); /* per-PRU-device state for minors 0,1 */
  ITCPktDeviceState * (mPktDeviceState[PKT_MINORS]); /* per-packet-device state for minors 2,3 */
  ITCEvtDeviceState * (mEvtDeviceState[EVT_MINORS]); /* per-event-device state for minor 4,5 */
  ITCMFMDeviceState * (mMFMDeviceState[MFM_MINORS]); /* per-ITCMFM-device state for minor 6..11 */

  ITCKThreadState mOBPktThread;
  ITCKThreadState mKITCLevelThread;
#if 0
  struct task_struct * mShipOBPktTask;     /* kthread to push packets to PRUs */
  wait_queue_head_t mOBWaitQueue;          /* wait queue for mShipOBPktTask */
#endif
} ITCModuleState;

extern ITCModuleState S;

/*** PUBLIC FUNCTIONS */

bool isITCEnabledStatusByDir8(int dir8) ;

ssize_t trySendUrgentRoutedKernelPacket(const u8 *pkt, size_t count) ;

#endif /* ITC_PKT_H */
