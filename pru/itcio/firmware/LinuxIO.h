#ifndef LINUXIO_H                /* -*- C -*- */
#define LINUXIO_H
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

#include <stdint.h>
#include <pru_ctrl.h>
#include "prux.h"

extern void initLinuxIO();

extern unsigned processPackets();

extern int CSendVal(const char * str1, const char * str2, uint32_t val);

extern int CSendFromThread(uint32_t prudir, const char * str, uint32_t val);

extern int CSendTagFromThread(uint32_t prudir, const char * str, uint16_t val);

extern int CSendPacket(uint8_t * data, uint32_t len);

extern void fillFail(const char * msg, uint8_t * packet, uint16_t len);

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

#endif /* LINUXIO_H */
