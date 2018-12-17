#ifndef THREADS_H                /* -*- C -*- */
#define THREADS_H
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
 */

#include <stdint.h>

extern void mainLoop(void);
extern void setPacketRunnerEnable(uint32_t prudir, uint32_t boolEnableValue);
extern void copyOutScratchPad(uint8_t * packet, uint16_t len);
extern unsigned addfuncasm(unsigned a, unsigned b);

#endif /* THREADS_H */
