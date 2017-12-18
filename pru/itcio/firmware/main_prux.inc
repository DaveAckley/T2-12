/* -*- c -*- */
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
 * Author: Dave Ackley <ackley@ackleyshack.com>
 *
 */

#include "prux.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h> /* for strlen */
#include <pru_cfg.h>
#include <pru_ctrl.h>
#include <pru_intc.h>
#include <rsc_types.h>
#include <pru_virtqueue.h>
#include <pru_rpmsg.h>
#include "resource_table_x.h"

volatile register uint32_t __R31;
volatile register uint32_t __R30;
volatile register uint32_t __R31;

/*
 * Used to make sure the Linux drivers are ready for RPMsg communication
 * Found at linux-x.y.z/include/uapi/linux/virtio_config.h
 */
#define VIRTIO_CONFIG_S_DRIVER_OK	4

uint8_t payload[RPMSG_BUF_SIZE];

extern int addfuncasm(int a, int b);
extern void initStateMachines();
extern void mainLoop();
extern void advanceStateMachines();
extern unsigned processOutboundITCPacket(uint8_t * packet, uint16_t len);
extern void copyOutScratchPad(uint8_t * packet, uint16_t len);

static struct pru_rpmsg_transport transport;
static unsigned firstPacket = 1;
static uint16_t firstSrc, firstDst;

int sendVal(const char * str1, const char * str2, uint32_t val)
{
  enum { BUF_LEN = 50 };
  char buf[BUF_LEN];
  int len = 0;
  int i;

  if (firstPacket) return 0; /* Not ready yet */
  buf[len++] = 0xc1; /* here comes a 'local standard' packet type 1 */

  /* First the value in hex */
  for (i = 0; i < 8; ++i) {
    buf[len++] = "0123456789abcdef"[val>>28];
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

void fillFail(const char * msg, uint8_t * packet, uint16_t len)
{
  uint32_t i;
  for (i = 1; i < len; ++i) {
    const char ch = msg[i-1];
    if (!ch) break;
    packet[i] = ch;
  }
}

unsigned processSpecialPacket(uint8_t * packet, uint16_t len)
{
  unsigned i;
  if (len == 0) return 0; /* or assert? */
  switch (packet[0]) {

  /* PACKET TYPE: '*' Wildcard debug, content non-standardized, can change at will */
  case '*': {                        
    if (len < 4) fillFail("[PKLEN]",packet,len);
    else {
      int32_t a = packet[1];
      int32_t b = packet[2];
      int32_t ret = addfuncasm(a,b);
      packet[3] = (uint8_t) ret;
    }
    break;
  }


  /* PACKET TYPE: write 'B'it of R30 (return old value) */
  case 'B': {                        
    if (len < 3) fillFail("[PKLEN]",packet,len);
    else {
      uint32_t bitnum = packet[1];
      uint32_t mask = 1<<bitnum;
      uint32_t oldval = (__R30 & mask) ? 1 : 0;
      uint32_t newval = packet[2];
      if (bitnum > 31 || newval > 1) fillFail("[INVAL]",packet,len);
      else {
        if (newval) __R30 |= mask;
        else __R30 &= ~mask;
        packet[2] = oldval;
      }
    }
    break;
  }

  /* PACKET TYPE: 'W'rite R30 (and then R31) */
  case 'W': {                        
    uint32_t tmp = 0;
    uint32_t tlen = len;
    if (tlen > 5) tlen = 5;
    for (i = 1; i < tlen; ++i) {
      tmp |= packet[i]<<((i-1)<<3);
    }
    __R30 = tmp;
  }
  /* FALL THROUGH INTO CASE 'R' */

  /* PACKET TYPE: 'R'ead R31 */
  case 'R': {                        
    uint32_t r31 = __R31;
    if (len > 5) len = 5;
    for (i = 1; i < len; ++i) {
      packet[i] = r31&0xff;
      r31 >>=8;
    }
    break;
  }

    /* PACKET TYPE: 'S'cratchpad memory read */
  case 'S': {                        
    if (len > 4)
      copyOutScratchPad(&packet[4], len-4);
    else
      fillFail("[PKLEN]",packet,len);
    break;
  }

  default:
    {
      fillFail("[PKTYP]",packet,len);
      break;
    }
  }
  return 1;
}

/*
* main.c
*/
void main(void)
{
  volatile uint8_t *status,number;

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

  /* Never look back */
  mainLoop();
}

int processPackets() {
  uint16_t src, dst, len;
    
  /* Check bit 30 or 31 of register R31 to see if the ARM has kicked us */
  /* Also check once per second if no kicks -- some interrupts get missed? grr */
  if ((__R31 & HOST_INT) || PRUX_CTRL.CYCLE > 200000000) { 
    
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
        if (payload[0]&0x80) ret = processOutboundITCPacket(payload,len);
        else ret = processSpecialPacket(payload,len);

        if (ret) {
          /* Return the processed packet back to where it came from */
          pru_rpmsg_send(&transport, dst, src, payload, len);
        }
      }
    }
  }
  return firstPacket;
}
