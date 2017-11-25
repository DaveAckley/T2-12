/* -*- c -*- */
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
extern void advanceStateMachines();

static struct pru_rpmsg_transport transport;
static unsigned firstPacket = 1;
static uint16_t firstSrc, firstDst;

int sendVal(const char * str, uint32_t val)
{
  enum { BUF_LEN = 50 };
  char buf[BUF_LEN];
  int len = 0;
  int i;

  if (firstPacket) return 0; /* Not ready yet */
  buf[len++] = 'V'; /* here comes a debug Value */

  /* First the value in hex */
  for (i = 0; i < 8; ++i) {
    buf[len++] = "0123456789abcdef"[val>>28];
    val <<= 4;
  }

  /* Then a space */
  buf[len++] = ' ';

  /* Then the string if any */
  if (str) {
    /* Take as much string as we can hold */
    while (len < BUF_LEN-2 && *str) buf[len++] = *str++;
  }
  buf[len++] = '\0';

  /* Send it */
  pru_rpmsg_send(&transport, firstDst, firstSrc, buf, len);
  return 1;  
}

/*
* main.c
*/
void main(void)
{
  uint16_t src, dst, len;
  volatile uint8_t *status,number;

  /* allow OCP master port access by the PRU so the PRU can read external memories */
  CT_CFG.SYSCFG_bit.STANDBY_INIT = 0;

  CT_CFG.SYSCFG_bit.STANDBY_INIT = 0;

  PRUX_CTRL.CTRL_bit.CTR_EN = 1;   /* turn on our cycle counter */

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

  /* Fire up the bit bangers for the packet comms */
  initStateMachines();

  while (1) {

    /* Move them bits!  Push them out!  Pull them in! */
    advanceStateMachines();
    
    /* Check bit 30 or 31 of register R31 to see if the ARM has kicked us */
    /* Also check once per second if no kicks -- some interrupts get missed? grr */
    if ((__R31 & HOST_INT) || PRUX_CTRL.CYCLE > 200000000) { 

      /* Clear the event status */
      CT_INTC.SICR_bit.STS_CLR_IDX = FROM_ARM_HOST;

      /* Reset timeout clock */
      PRUX_CTRL.CYCLE = 0;

      /* Receive all available messages, multiple messages can be sent per kick */
      while (pru_rpmsg_receive(&transport, &src, &dst, payload, &len) == PRU_RPMSG_SUCCESS) {

        if (firstPacket) {
          firstSrc = src;
          firstDst = dst;
          pru_rpmsg_send(&transport, firstDst, firstSrc, PRU_NAME, strlen(PRU_NAME));
          firstPacket = 0;
        }

        /* Echo the message back to the same address from which we just received */
        payload[0]++; /* But increment the first byte to show we care */
        payload[0] = addfuncasm(payload[0]+1, ON_PRU); /* add extra increments via asm */
        pru_rpmsg_send(&transport, dst, src, payload, len);					
      }
    }
  }
}

