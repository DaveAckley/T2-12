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

extern void initLinuxIO();

extern int processPackets();

extern int CSendVal(const char * str1, const char * str2, uint32_t val);

extern int CSendFromThread(uint32_t prudir, uint32_t code1, uint32_t code2, uint32_t val);

extern int CSendTagFromThread(uint32_t prudir, const char * str, uint16_t val);

extern int CSendPacket(uint8_t * data, uint32_t len);

extern void fillFail(const char * msg, uint8_t * packet, uint16_t len);

#endif /* LINUXIO_H */
