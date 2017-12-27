#ifndef BUFFERS_H                /* -*- C -*- */
#define BUFFERS_H
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

#include "prux.h"

/* Packet type (first byte) information. */
#define PKT_ROUTED_STD_MASK 0xc0
#define PKT_ROUTED_STD_VALUE 0x80

#define PKT_LOCAL_STD_MASK 0xc0
#define PKT_LOCAL_STD_VALUE 0xc0

#define PKT_STD_OVERRUN_MASK 0x10
#define PKT_STD_OVERRUN_VALUE 0x10

#define PKT_STD_ERROR_MASK 0x08
#define PKT_STD_ERROR_VALUE 0x08

#define PKT_STD_DIRECTION_MASK 0x07


/* Simple lame-o ring buffer. */
#define RING_BUFFER_BITS 9
#define RING_BUFFER_SIZE (1<<RING_BUFFER_BITS)
#define RING_BUFFER_MASK ((1<<RING_BUFFER_BITS)-1)

struct OutboundRingBuffer {
  unsigned short writePtr;      /* Points at first unused byte after end of newest packet*/
  unsigned short readPtr;       /* Points at LENGTH BYTE at front of oldest packet */
  unsigned char buffer[RING_BUFFER_SIZE];
};

inline unsigned int orbUsedBytes(struct OutboundRingBuffer * orb) {
  int diff = orb->writePtr - orb->readPtr;
  if (diff < 0) diff += RING_BUFFER_SIZE;
  return (unsigned int) diff;
}

inline unsigned int orbAvailableBytes(struct OutboundRingBuffer * orb) {
  return RING_BUFFER_SIZE - orbUsedBytes(orb) - 1;
}

inline int orbStoreByte(struct OutboundRingBuffer * orb, unsigned char byte) {
  if (orbAvailableBytes(orb) == 0) return 0;
  orb->buffer[orb->writePtr] = byte;
  orb->writePtr = (orb->writePtr+1) & RING_BUFFER_MASK;
  return 1;
}

inline unsigned int dircodeFromPrudir(unsigned prudir) {
  switch (prudir) {
  case 0: return DIRCODE_FOR_PRUDIR0;
  case 1: return DIRCODE_FOR_PRUDIR1;
  case 2: return DIRCODE_FOR_PRUDIR2;
  default:
    return 0; /*which is an illegal code in this context*/
  }
}

extern int orbAddPacket(struct OutboundRingBuffer * orb, unsigned char * data, unsigned char len) ;

inline unsigned int orbFrontPacketLenInline(struct OutboundRingBuffer * orb) {
  if (orbUsedBytes(orb) == 0) return 0;
  return orb->buffer[orb->readPtr];
}

extern unsigned int orbFrontPacketLen(unsigned prudir) ;

inline int orbDropFrontPacketInline(struct OutboundRingBuffer * orb) {
  unsigned int len = orbFrontPacketLenInline(orb);
  if (len == 0) return 0;
  orb->readPtr = (orb->readPtr + len + 1) & RING_BUFFER_MASK;
  return 1;
}

extern int orbDropFrontPacket(unsigned prudir) ;

inline int orbFrontPacketStartIndex(struct OutboundRingBuffer * orb) {
  if (!orbUsedBytes(orb))
    return -1;
  return (orb->readPtr + 1) &  RING_BUFFER_MASK;
}

inline unsigned char orbGetFrontPacketByteInline(struct OutboundRingBuffer * orb, unsigned idxInPacket) {
  unsigned int base = orbFrontPacketStartIndex(orb);
  unsigned int index = (base + idxInPacket) & RING_BUFFER_MASK;
  return orb->buffer[index];
}

extern unsigned char orbGetFrontPacketByte(unsigned prudir, unsigned idxInPacket) ;

extern void ipbWriteByte(unsigned prudir, unsigned char idxInPacket, unsigned byteToWrite) ;

extern void ipbReportFrameError(unsigned prudir, unsigned char packetLength,
                                unsigned ct0,
                                unsigned ct1,
                                unsigned ct2,
                                unsigned ct3,
                                unsigned ct4,
                                unsigned ct5,
                                unsigned ct6,
                                unsigned ct7) ;

/*return non-zero if non-empty packet actually sent*/
extern int ipbSendPacket(unsigned prudir, unsigned char length) ;

#define MAX_PACKET_SIZE 256

struct InboundPacketBuffer {
  unsigned char buffer[MAX_PACKET_SIZE];
};

struct PruDirBuffers {
  struct OutboundRingBuffer out;
  struct InboundPacketBuffer in;
};

struct PruDirs {
  struct PruDirBuffers pruDirBuffers[3];
};

extern struct PruDirs pruDirData;

inline struct PruDirBuffers * pruDirToBuffers(unsigned prudir) {
  return &pruDirData.pruDirBuffers[prudir&3];
}

inline struct OutboundRingBuffer * pruDirToORB(unsigned prudir) {
  return &pruDirToBuffers(prudir)->out;
}

inline struct InboundPacketBuffer * pruDirToIPB(unsigned prudir) {
  return &pruDirToBuffers(prudir)->in;
}

#endif /* BUFFERS_H */
