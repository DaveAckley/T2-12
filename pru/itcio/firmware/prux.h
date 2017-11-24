/* PRU-specific (PRU0 vs PRU1) definitions  -*- C -*- */
#ifndef PRUX_H
#define PRUX_H

#ifndef PRU
#error Symbol PRU must be defined
#endif

#define xstr(a) str(a)
#define str(a) #a

#define HOST_UNUSED 255

#if PRU==0

#define TO_ARM_HOST	16	
#define FROM_ARM_HOST	17
#define HOST_INT_BIT    30
#define PRU0_TO_ARM_CHANNEL  2
#define PRU0_FROM_ARM_CHANNEL 0
#define PRU1_TO_ARM_CHANNEL  HOST_UNUSED
#define PRU1_FROM_ARM_CHANNEL HOST_UNUSED
#define TO_ARM_CHANNEL  PRU0_TO_ARM_CHANNEL
#define FROM_ARM_CHANNEL PRU0_FROM_ARM_CHANNEL

#elif PRU==1

#define TO_ARM_HOST	18	
#define FROM_ARM_HOST	19
#define HOST_INT_BIT    31
#define PRU1_TO_ARM_CHANNEL  3
#define PRU1_FROM_ARM_CHANNEL 1
#define PRU0_TO_ARM_CHANNEL  HOST_UNUSED
#define PRU0_FROM_ARM_CHANNEL HOST_UNUSED
#define TO_ARM_CHANNEL  PRU1_TO_ARM_CHANNEL
#define FROM_ARM_CHANNEL PRU1_FROM_ARM_CHANNEL

#else
#error Must define symbol PRU to be either 0 or 1
#endif

#define HOST_INT   ((uint32_t) 1 << HOST_INT_BIT) /* 0x40000000 / 0x80000000 */
/*
 * Using the name 'itc-pkt' will (supposedly, someday?) probe the
 * itc_pkt driver found at /lib/modules/4.4.54-ti-r93/itc/itc_pkt.ko
 */
#define CHAN_NAME  "itc-pkt"
#define CHAN_DESC  "Channel " xstr(HOST_INT_BIT) 
#define CHAN_PORT  (HOST_INT_BIT)

#endif /* PRUX_H */
