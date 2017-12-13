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
#define PROC_FIFO "itc-pkt-fifo"

/* PRU special packets are expected to be smaller and rarer.  Give them 1KB each */
#define SPECIAL_KFIFO_SIZE (1<<10)

/* REC_1 for one byte record lengths is perfect for us.. */
typedef STRUCT_KFIFO_REC_1(KFIFO_SIZE) ITCPacketFIFO;
typedef STRUCT_KFIFO_REC_1(SPECIAL_KFIFO_SIZE) SpecialPacketFIFO;

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

typedef struct itc_pkt_driver_state {
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

/*PIN INFO MACRO MAPS*/
/* direction to pru# */
#define ITC_DIR_TO_PRU__NE 1
#define ITC_DIR_TO_PRU__ET 0
#define ITC_DIR_TO_PRU__SE 0
#define ITC_DIR_TO_PRU__SW 0
#define ITC_DIR_TO_PRU__WT 1
#define ITC_DIR_TO_PRU__NW 1
#define ITC_DIR_TO_PRU(dir) ITC_DIR_TO_PRU__##dir

/* direction to prudir# */
#define ITC_DIR_TO_PRUDIR__NE 2
#define ITC_DIR_TO_PRUDIR__ET 0
#define ITC_DIR_TO_PRUDIR__SE 1
#define ITC_DIR_TO_PRUDIR__SW 2
#define ITC_DIR_TO_PRUDIR__WT 0
#define ITC_DIR_TO_PRUDIR__NW 1
#define ITC_DIR_TO_PRUDIR(dir) ITC_DIR_TO_PRUDIR__##dir

/* pru# + prudir# to direction */
#define ITC_PRU_PRU_DIR_TO_DIR__0_0 ET
#define ITC_PRU_PRU_DIR_TO_DIR__0_1 SE
#define ITC_PRU_PRU_DIR_TO_DIR__0_2 NW
#define ITC_PRU_PRU_DIR_TO_DIR__1_0 WT
#define ITC_PRU_PRU_DIR_TO_DIR__1_1 NW
#define ITC_PRU_PRU_DIR_TO_DIR__1_2 NE
#define ITC_PRU_PRU_DIR_TO_DIR(pru,prudir)ITC_PRU_PRU_DIR_TO_DIR__##pru##_##prudir

/* pin name to itc pin number */
#define ITC_PIN_NAME_TO_PIN_NUMBER__TXRDY 0
#define ITC_PIN_NAME_TO_PIN_NUMBER__TXDAT 1
#define ITC_PIN_NAME_TO_PIN_NUMBER__RXRDY 2
#define ITC_PIN_NAME_TO_PIN_NUMBER__RXDAT 3
#define ITC_PIN_NAME_TO_PIN_NUMBER(pname) ITC_PIN_NAME_TO_PIN_NUMBER__##pname

/* dir+name to R30 output/R31 output pin numbers */
#define ITC_DIR_NAME_TO_R30_PIN__NE_TXRDY 10
#define ITC_DIR_NAME_TO_R30_PIN__NE_TXDAT 11
#define ITC_DIR_NAME_TO_R31_PIN__NE_RXRDY 4
#define ITC_DIR_NAME_TO_R31_PIN__NE_RXDAT 5

#define ITC_DIR_NAME_TO_R30_PIN__ET_TXRDY 3
#define ITC_DIR_NAME_TO_R30_PIN__ET_TXDAT 4
#define ITC_DIR_NAME_TO_R31_PIN__ET_RXRDY 0
#define ITC_DIR_NAME_TO_R31_PIN__ET_RXDAT 1

#define ITC_DIR_NAME_TO_R30_PIN__SE_TXRDY 5
#define ITC_DIR_NAME_TO_R30_PIN__SE_TXDAT 6
#define ITC_DIR_NAME_TO_R31_PIN__SE_RXRDY 2
#define ITC_DIR_NAME_TO_R31_PIN__SE_RXDAT 14

#define ITC_DIR_NAME_TO_R30_PIN__SW_TXRDY 7
#define ITC_DIR_NAME_TO_R30_PIN__SW_TXDAT 14
#define ITC_DIR_NAME_TO_R31_PIN__SW_RXRDY 15
#define ITC_DIR_NAME_TO_R31_PIN__SW_RXDAT 16

#define ITC_DIR_NAME_TO_R30_PIN__WT_TXRDY 0
#define ITC_DIR_NAME_TO_R30_PIN__WT_TXDAT 1
#define ITC_DIR_NAME_TO_R31_PIN__WT_RXRDY 6
#define ITC_DIR_NAME_TO_R31_PIN__WT_RXDAT 7

#define ITC_DIR_NAME_TO_R30_PIN__NW_TXRDY 8
#define ITC_DIR_NAME_TO_R30_PIN__NW_TXDAT 9
#define ITC_DIR_NAME_TO_R31_PIN__NW_RXRDY 2
#define ITC_DIR_NAME_TO_R31_PIN__NW_RXDAT 3

#define ITC_DIR_AND_PIN_TO_R30_BIT(dir,pin) ITC_DIR_NAME_TO_R30_PIN__##dir##_##pin
#define ITC_DIR_AND_PIN_TO_R31_BIT(dir,pin) ITC_DIR_NAME_TO_R31_PIN__##dir##_##pin

/* MACRO ITERATORS */
#define FOR_XX_IN_ITC_ALL_DIR XX(NE) XX(ET) XX(SE) XX(SW) XX(WT) XX(NW)
#define FOR_XX_IN_ITC_ALL_PRUDIR XX(0) XX(1) XX(2)
  
#endif /* ITC_PKT_H */
