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

#define PRU_MAX_DEVICES 2       /* PRU0, PRU1*/
#define MINOR_DEVICES (PRU_MAX_DEVICES+1)  /* +1 for the ITC packet interface */
#define RPMSG_BUF_SIZE 512
#define MAX_PACKET_SIZE (RPMSG_BUF_SIZE-sizeof(struct rpmsg_hdr))

/* ITC packets are max 255.  Guarantee space for 16 (256*16 == 4,096 == 2**12) */
#define KFIFO_SIZE (1<<12)
/*unused? #define PROC_FIFO "itc-pkt-fifo"*/

/* PRU special packets are expected to be smaller and rarer.  Give them 1KB each */
#define SPECIAL_KFIFO_SIZE (1<<10)

/* REC_1 for one byte record lengths is perfect for us.. */
typedef STRUCT_KFIFO_REC_1(KFIFO_SIZE) ITCPacketFIFO;
typedef STRUCT_KFIFO_REC_1(SPECIAL_KFIFO_SIZE) SpecialPacketFIFO;

typedef enum debug_flags {
  DBG_PKT_RCVD = 0x00000001,
  DBG_PKT_SENT = 0x00000002,
} DebugFlags;

#define DBGIF(mask) if ((mask)&S.debugFlags)
#define DBGPRINTK(mask, printkargs...) do { DBGIF(mask) printk(printkargs); } while (0);
#define DBGPRINT_HEX_DUMP(mask, printhexdumpargs...) do { DBGIF(mask) print_hex_dump(printhexdumpargs); } while (0);

/* per maj,min device -- so in our case, per PRU */
typedef struct itc_dev_state {
  struct rpmsg_channel *rpmsg_dev;
  struct device *dev;
  struct mutex specialLock; /*if held, a special packet roundtrip is in progress*/
  wait_queue_head_t specialWaitQ;
  bool dev_lock;
  struct cdev cdev;
  dev_t devt;
} ITCDeviceState;

/* 'global' state, so far as we can structify it */
typedef struct itc_pkt_driver_state {
  DebugFlags        debugFlags;
  dev_t             major_devt;     /* our dynamically-allocated major device number */
  ITCPacketFIFO     itcPacketKfifo; /* buffer for all inbound standard packets */
  SpecialPacketFIFO special0Kfifo;  /* buffer for inbound special packets from PRU0 */
  SpecialPacketFIFO special1Kfifo;  /* buffer for inbound special packets from PRU1 */
  struct mutex      read_lock;      /* lock for read access (no lock for write access - rpmsg cb will be only writer) */
  int               open_pru_minors;/* how many of our minors have (ever?) been opened */
  ITCDeviceState    * (dev_packet_state[MINOR_DEVICES]); /* ptrs to all our device states */
} ITCPacketDriverState;

extern __printf(5,6) int send_msg_to_pru(unsigned prunum,
                                         unsigned wait,
                                         char * buf,
                                         unsigned bugsiz,
                                         const char * fmt, ...);

extern ITCDeviceState * make_itc_minor(struct device * dev,
                                       int minor_obtained,
                                       int * err_ret);

#include "pin_info_maps.h"
  
#endif /* ITC_PKT_H */
