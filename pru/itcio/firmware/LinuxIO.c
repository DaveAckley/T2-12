
#include "prux.h"
#include "LinuxIO.h"
#include "Buffers.h"
#include "SpecialPackets.h"
#include "resource_table_x.h"
#include <rsc_types.h>
#include <pru_virtqueue.h>
#include <pru_rpmsg.h>
#include <pru_intc.h>
#include <pru_cfg.h>
#include <pru_ctrl.h>

/*
 * Used to make sure the Linux drivers are ready for RPMsg communication
 * Found at linux-x.y.z/include/uapi/linux/virtio_config.h
 */
#define VIRTIO_CONFIG_S_DRIVER_OK	4

static uint8_t payload[RPMSG_BUF_SIZE];
static struct pru_rpmsg_transport transport;
static unsigned firstPacket = 1;
static uint16_t firstSrc, firstDst;

static const char * (prudirnames[3]) = {
#if ON_PRU == 0
  "ET","SE","SW"
#else
  "WT","NW","NE"
#endif
};

int CSendFromThread(uint32_t prudir, const char * str, uint32_t val)
{
  enum { BUF_LEN = 50 };
  char buf[BUF_LEN];
  int len = 0;
  int i;

  if (firstPacket) return 0; /* Not ready yet */

  buf[len++] = 0xc1; /* here comes a 'local standard' packet type 1 */

  buf[len++] = '0'+ON_PRU;
  if (prudir < 3) {
    buf[len++] = prudirnames[prudir][0];
    buf[len++] = prudirnames[prudir][1];
  } else {
    buf[len++] = 'a'+prudir;
  }
  buf[len++] = ':';
  
  /* Next the value in hex */
  for (i = 0; i < 8; ++i) {
    uint8_t h = val>>28;
    buf[len++] = h < 10 ? '0' + h : 'a' - 10 + h;
    val <<= 4;
  }

  /* Then a space */
  buf[len++] = ' ';

  /* Then as much of the string that fits */
  if (str) while (len < BUF_LEN-1 && *str) buf[len++] = *str++;

  /* Send it */
  pru_rpmsg_send(&transport, firstDst, firstSrc, buf, len);

  /* Distract the destroyer to give our packet time to get away */
  {
    volatile unsigned wastoid = 0;
    while (++wastoid < 2000000) ;
  }
  

  return 1;  
}

static unsigned char tagspinner = 0;

int CSendTagFromThread(uint32_t prudir, const char * str, uint16_t val)
{
  enum { BUF_LEN = 50 };
  char buf[BUF_LEN];
  int len = 0;
  int i;

  if (firstPacket) return 0; /* Not ready yet */

  buf[len++] = 0xc2; /* here comes a 'local standard' packet type 2 */

  buf[len++] = ++tagspinner; /*mark tag msgs sequentially to help detect missed tags*/
  if (prudir < 3) {
    buf[len++] = prudirnames[prudir][0];
    buf[len++] = prudirnames[prudir][1];
  } else {
    buf[len++] = 'a'+prudir;
  }
  buf[len++] = ':';
  
  /* Next the 16-bit value in hex */
  for (i = 0; i < 4; ++i) {
    uint8_t h = val>>12;
    buf[len++] = h < 10 ? '0' + h : 'a' - 10 + h;
    val <<= 4;
  }

  /* Then a space */
  buf[len++] = ' ';

  /* Then as much of the string that fits */
  if (str) while (len < BUF_LEN-1 && *str) buf[len++] = *str++;

  /* Send it */
  pru_rpmsg_send(&transport, firstDst, firstSrc, buf, len);

  /* Distract the destroyer to give our packet time to get away */
  {
    volatile unsigned wastoid = 0;
    while (++wastoid < 1000000) ;
  }
  
  return 1;  
}


int CSendPacket(uint8_t * data, uint32_t len)
{
  if (firstPacket) return 0; /* Not ready yet */
  pru_rpmsg_send(&transport, firstDst, firstSrc, data, len);
  return 1;  
}


/**
   Reset and re-enable the cycle counter.  According to SPRU8FHA,
   Table 29, page 80, the cycle counter (1) Does not wrap at
   0xffffffff, but instead disables counting, and (2) Can be cleared
   when it is disabled.

   On the other hand, though, two points: (A) It should be highly
   unlikely for the cycle counter to hit the max in the loop below,
   and (B) I have code that, apparently, was successfully clearing the
   cycle counter without disabling it first.

   So given (A) and (b) we 'ought to be fine' just clearing the
   counter on the fly, but out of an abundance of caution we are
   writing and using this routine instead anyway.
 */
static inline void resetCycleCounter() {
  PRUX_CTRL.CTRL_bit.CTR_EN = 0;   /* disable cycle counter */
  PRUX_CTRL.CYCLE = 0;             /* clear it while disabled */
  PRUX_CTRL.CTRL_bit.CTR_EN = 1;   /* and re-enable counting */
}

void initLinuxIO() {
  volatile uint8_t *status, number;

  /* allow OCP master port access by the PRU so the PRU can read external memories */
  CT_CFG.SYSCFG_bit.STANDBY_INIT = 0;

  /* enable XFR 'register shifting', which the state machines use for context switching */
  CT_CFG.SPP_bit.XFR_SHIFT_EN = 1;

  /* enable our cycle counter */
  resetCycleCounter();

  /* clear the status of the PRU-ICSS system event that the ARM will use to 'kick' us */
  CT_INTC.SICR_bit.STS_CLR_IDX = FROM_ARM_HOST;
  
  /* Make sure the Linux drivers are ready for RPMsg communication */
  status = &resourceTable.rpmsg_vdev.status;
  while (!(*status & VIRTIO_CONFIG_S_DRIVER_OK));
  
  /* Initialize pru_virtqueue corresponding to vring0 (PRU to ARM Host direction) */
  pru_virtqueue_init(&transport.virtqueue0, &resourceTable.rpmsg_vring0, TO_ARM_HOST, FROM_ARM_HOST);
  
  /* Initialize pru_virtqueue corresponding to vring1 (ARM Host to PRU direction) */
  pru_virtqueue_init(&transport.virtqueue1, &resourceTable.rpmsg_vring1, TO_ARM_HOST, FROM_ARM_HOST);
  
  /* Create the RPMsg channel between the PRU and ARM user space using the transport structure. */
  while (pru_rpmsg_channel(RPMSG_NS_CREATE, &transport, CHAN_NAME, CHAN_DESC, CHAN_PORT) != PRU_RPMSG_SUCCESS);
}

int CSendVal(const char * str1, const char * str2, uint32_t val)
{
  enum { BUF_LEN = 50 };
  char buf[BUF_LEN];
  int len = 0;
  int i;

  if (firstPacket) return 0; /* Not ready yet */
  buf[len++] = 0xc1; /* here comes a 'local standard' packet type 1 */

  /* First the value in hex */
  for (i = 0; i < 8; ++i) {
    uint8_t h = val>>28;
    buf[len++] = h < 10 ? '0' + h : 'a' - 10 + h;
    val <<= 4;
  }

  /* Then a space */
  buf[len++] = ' ';

  /* Then as much of the strings, if any, that fit */
  if (str1) while (len < BUF_LEN-1 && *str1) buf[len++] = *str1++;
  if (str2) while (len < BUF_LEN-1 && *str2) buf[len++] = *str2++;

  /* Send it */
  pru_rpmsg_send(&transport, firstDst, firstSrc, buf, len);
  return 1;  
}

/*Given packet!=0 && len > 0.  Return 0 if OK */
unsigned processOutboundITCPacket(uint8_t * packet, uint16_t len) {
  unsigned type = packet[0];
  unsigned dircode = type & PKT_STD_DIRECTION_MASK;
  unsigned prudir;
  switch (dircode) {
  case DIRCODE_FOR_PRUDIR0: prudir = 0; break;
  case DIRCODE_FOR_PRUDIR1: prudir = 1; break;
  case DIRCODE_FOR_PRUDIR2: prudir = 2; break;
  default:
    packet[0] |= PKT_STD_ERROR_VALUE;
    return 1; /*this packet doesn't belong here*/
  }
  {
    struct OutboundRingBuffer * orb = &pruDirData.pruDirBuffers[prudir].out;
    if (orbAddPacket(orb, packet, len)) {
      packet[0] |= PKT_STD_OVERRUN_VALUE;
      return 1; /*no room at the inn*/
    }
    return 0;
  }
}
void fillFail(const char * msg, uint8_t * packet, uint16_t len)
{
  uint32_t i;
  for (i = 1; i < len; ++i) {
    const char ch = msg[i-1];
    if (!ch) break;
    packet[i] = ch;
  }
}


int processPackets() {
  uint16_t src, dst, len;
    
  /* Check bit 30 or 31 of register R31 to see if the ARM has kicked us */
  /* Also check once per second if no kicks -- some interrupts get missed? grr */
  /* ..except caller has now done that checking.. */
  /*if ((__R31 & HOST_INT) || PRUX_CTRL.CYCLE > 200000000) */ { 
    
    /* Clear the event status */
    CT_INTC.SICR_bit.STS_CLR_IDX = FROM_ARM_HOST;

    /* Reset timeout clock */
    resetCycleCounter();

    /* Receive all available messages, multiple messages can be sent per kick */
    while (pru_rpmsg_receive(&transport, &src, &dst, payload, &len) == PRU_RPMSG_SUCCESS) {

      if (firstPacket) {
        /* linux sends an empty packet to get us going */
        firstSrc = src;
        firstDst = dst;
        firstPacket = 0;
      }

      if (len > 0) {
        unsigned ret;
        if ((payload[0] & PKT_ROUTED_STD_MASK) == PKT_ROUTED_STD_VALUE)
          ret = processOutboundITCPacket(payload,len);
        else
          ret = processSpecialPacket(payload,len);

        if (ret) {
          /* Return the processed packet back to where it came from */
          pru_rpmsg_send(&transport, dst, src, payload, len);
        }
      }
    }
  }
  return firstPacket;
}



