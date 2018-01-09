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

#define PKT_BULK_STD_MASK 0x20
#define PKT_BULK_STD_VALUE 0x20

#define PKT_STD_OVERRUN_MASK 0x10
#define PKT_STD_OVERRUN_VALUE 0x10

#define PKT_STD_ERROR_MASK 0x08
#define PKT_STD_ERROR_VALUE 0x08

#define PKT_STD_DIRECTION_MASK 0x07

inline unsigned int dircodeFromPrudir(unsigned prudir) {
  switch (prudir) {
  case 0: return DIRCODE_FOR_PRUDIR0;
  case 1: return DIRCODE_FOR_PRUDIR1;
  case 2: return DIRCODE_FOR_PRUDIR2;
  default:
    return 0; /*which is an illegal code in this context*/
  }
}

extern void ppbWriteInboundByte(unsigned prudir, unsigned char idxInPacket, unsigned byteToWrite) ;

extern int ppbReadOutboundByte(unsigned prudir, unsigned char idxInPacket) ;

extern void ppbReportFrameError(unsigned prudir, unsigned char packetLength,
                                unsigned ct0,
                                unsigned ct1,
                                unsigned ct2,
                                unsigned ct3,
                                unsigned ct4,
                                unsigned ct5,
                                unsigned ct6,
                                unsigned ct7) ;

/*return 0 if packet shipped, -PBE_BUSY if caller needs to wait and try again */
extern int ppbSendInboundPacket(unsigned prudir, unsigned char length) ;

/*return 0 if no packet available, >0 packet length on success */
extern int ppbReceiveOutboundPacket(unsigned prudir) ;


/*MAX_PACKET_SIZE cannot be changed without redesigning asm code!*/
#define MAX_PACKET_SIZE (1<<8)

struct PRUPacketBufferStats {
  unsigned packetTransfers;     /* Count of packet-wise transfers in or out of this buffer */
  unsigned packetStalls;        /* Count of packet transfer retries */
  unsigned packetDrops;         /* Count of packet transfer failures */
  unsigned char flags;          /* NEED_KICK, .. */
};

enum PruPacketBufferFlags {
  NEED_KICK = 0x01,             /* We want to kick ARM but haven't yet succeeded */
};

typedef unsigned char PRUPacketBuffer[MAX_PACKET_SIZE];
struct PRUDirBuffers {
  PRUPacketBuffer outbuffer;  /*At struct PRUDirBuffers* + 0*/
  PRUPacketBuffer inbuffer;   /*At struct PRUDirBuffers* + 256*/
  struct PRUPacketBufferStats outstats;
  struct PRUPacketBufferStats instats;
};

struct PruDirs {
  struct PRUDirBuffers pruDirBuffers[3];
};

extern struct PruDirs pruDirData;

inline struct PRUDirBuffers * pruDirToBuffers(unsigned prudir) {
  return &pruDirData.pruDirBuffers[prudir&3];
}

/*
inline struct PRUPacketBuffer * pruDirToInPPB(unsigned prudir) {
  return &pruDirToBuffers(prudir)->in;
}

inline struct PRUPacketBuffer * pruDirToOutPPB(unsigned prudir) {
  return &pruDirToBuffers(prudir)->out;
}
*/

#endif /* BUFFERS_H */
