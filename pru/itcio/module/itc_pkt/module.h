#ifndef MODULE_H
#define MODULE_H

#include <linux/kernel.h>
#include <linux/rpmsg.h>
#include <linux/slab.h>
#include <linux/fs.h>
#include <linux/init.h>
#include <linux/cdev.h>
#include <linux/module.h>
#include <linux/uaccess.h>
#include <linux/poll.h>

#include "ITCIterator.h"

#define PRU_MAX_DEVICES 2       /* PRU0, PRU1*/
#define MINOR_DEVICES (PRU_MAX_DEVICES+1)  /* +1 for the ITC packet interface */
#define RPMSG_BUF_SIZE 512

/*Note RPMSG takes up to 500+ but the ITCs need the length to fit in a byte */
#define RPMSG_MAX_PACKET_SIZE (RPMSG_BUF_SIZE-sizeof(struct rpmsg_hdr))
#define ITC_MAX_PACKET_SIZE 255

typedef enum debug_flags {
  DBG_PKT_RCVD    = 0x00000001, /*packets read*/
  DBG_PKT_SENT    = 0x00000002, /*packets written*/
  DBG_PKT_ROUTE   = 0x00000004, /*packets routed*/
  DBG_PKT_PRINTK  = 0x00000008, /*otherwise uncatergorized debug msgs*/
} DebugFlags;

#define Dbgif(mask) if ((mask)&S.debugFlags)
#define Dbgifprintk(mask, printkargs...) do { Dbgif(mask) printk(printkargs); } while (0)
#define Dbgprintk(printkargs...) Dbgifprintk(DBG_PKT_PRINTK, printkargs)
#define Dbgprint_hex_dump(mask, printhexdumpargs...) do { Dbgif(mask) print_hex_dump(printhexdumpargs); } while (0)

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
  wait_queue_head_t itcPacketWaitQ; /* for people blocking to reading standard packets */
  wait_queue_head_t itcWriteWaitQ ; /* for people blocking to write standard packets (to anywhere) */
  struct mutex      standardLock;   /* lock for reading standard packets */
  ITCIterator       itcIterator;    /* iterator for visiting priority pbs randomly */
  phys_addr_t       packetPhysP;    /* physical address of shared buffer space */
  struct SharedState * packetVirtP;    /* virtual address of shared buffer space */
  struct PacketBuffer *(fastInBufs[6]); /* cached ptrs to priority inbound buffers */
  struct task_struct *task;            /* itcpktThreadRunner task ptr */

  int               open_pru_minors;/* how many of our minors have (ever?) been opened */
  ITCDeviceState    * (dev_packet_state[MINOR_DEVICES]); /* ptrs to all our device states */
} ITCPacketDriverState;


extern int ship_packet_to_pru(unsigned prunum, unsigned wait, char * pkt, unsigned pktlen) ;

extern __printf(5,6) int send_msg_to_pru(unsigned prunum,
                                         unsigned wait,
                                         char * buf,
                                         unsigned bugsiz,
                                         const char * fmt, ...);

extern ITCDeviceState * make_itc_minor(struct device * dev,
                                       int minor_obtained,
                                       int * err_ret);

#include "pin_info_maps.h"
  
#endif /* MODULE_H */
