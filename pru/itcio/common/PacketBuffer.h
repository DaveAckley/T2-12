#ifndef PACKETBUFFER_H                /* -*- C -*- */
#define PACKETBUFFER_H
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

/* Packet type (first byte) information.
 *
 *     Packet Header Byte
 *      7    6    5    4     3    2    1    0
 *   +----+----+----+----+ +----+----+----+----+
 *   | SP | -- | -- | -- | | -- | -- | -- | -- |
 *   +----+----+----+----+ +----+----+----+----+
 *     ||
 * 1 Standard Packet
 * 0 Custom packet
 *
 *     Custom Packet Header Byte
 *      7    6    5    4     3    2    1    0
 *   +----+----+----+----+ +----+----+----+----+
 *   |  0 | B6 | B5 | B4 | | B3 | B2 | B1 | B0 |
 *   +----+----+----+----+ +----+----+----+----+
 *        \ MSB                             LSB/
 *         \------ seven bit ASCII code ------/
 *
 *
 *    Standard Packet Header Byte
 *      7    6    5    4     3    2    1    0
 *   +----+----+----+----+ +----+----+----+----+
 *   |  1 | ST | -- | -- | | -- | -- | -- | -- |
 *   +----+----+----+----+ +----+----+----+----+
 *          ||
 *    1 STatus packet
 *    0 Routed packet
 *
 *    Standard Routed Packet Header Byte
 *      7    6    5    4     3    2    1    0
 *   +----+----+----+----+ +----+----+----+----+
 *   | 1  | 0  | BR | OV | | ER | A2 | A1 | A0 |
 *   +----+----+----+----+ +----+----+----+----+
 *               ||   ||     ||   ||   ||   ||
 *         1 Bulk Rate||     ||   ||   ||  Address bit 0 (LSB)
 *         0 Priority ||     ||   ||  Address bit 1
 *                    ||     ||  Address bit 2 (MSB)
 *                 1 OVerrun ||
 *                 0 No overrun
 *                           ||
 *                         1 ERror
 *                         0 No error
 *
 *    Standard Status Packet Header Byte
 *      7    6    5    4     3    2    1    0
 *   +----+----+----+----+ +----+----+----+----+
 *   | 1  | 1  | SY | C1 | | C0 | A2 | A1 | A0 |
 *   +----+----+----+----+ +----+----+----+----+
 *               ||   ||     ||   ||   ||   ||
 *        1 Have SYnc ||     ||   ||   ||  Address bit 0 (LSB)
 *        0 No sync   ||     ||   ||   ||  Address bit 0 (LSB)
 *            Code bit 1     ||   ||  Address bit 1
 *                   Code bit 0  Address bit 2 (MSB)
 *
 * Standard Status Packet Codes (SY + C1 + C0)
 *  000 0 Sync lost due to clock timeout in this packet
 *  001 1 Sync lost due to frame error in this packet
 *  010 2 Sync lost due to wire overrun occurred during this packet
 *  011 3 Reserved3 (TBD, but sync is not present as of this report)

 *  100 4 Reserved4 (TBD, but sync is present as of this report)
 *  101 5 Reserved5 (TBD, but sync is present as of this report)
 *  110 6 Reserved6 (TBD, but sync is present as of this report)
 *  111 7 Packet sync achieved (1 byte packet)
 */

#ifdef __KERNEL__
#include <linux/string.h> /*for memset*/
#else
#include <string.h> /*for memset*/
#endif

/* IMPLEMENTATION NOTE:
 *
 * Although this is C code this header is also read by clpru for use
 * with assembler code, and in that context, certain minor things --
 * like, umm, macros with arguments -- DO NOT WORK.
 *
 * That (in addition to mere author bogosity) is why we have just
 * specific buffer sizes rather than arbitrary powers of 2, and why
 * things here in general seem so low-level and non-flexible.
 */

struct PacketBuffer {
  unsigned bufferSize;          /* Power of 2 size, in bytes, of buffer, below*/
  unsigned bufferMask;          /* bufferSize - 1*/
  unsigned writePtr;            /* Points at first unused byte after end of newest committed packet*/
  unsigned readPtr;             /* Points at LENGTH BYTE at front of oldest packet */
  unsigned packetsAdded;        /* Total packets added to this orb */
  unsigned packetsRejected;     /* Total packets not added due to insufficient space */
  unsigned packetsRemoved;      /* Total packets removed from this orb */
  unsigned short writeIdx;      /* Count of bytes written in not-yet-committed newest packet*/
  unsigned short readIdx;       /* Count of bytes read in not-yet-dropped oldest packet */
  unsigned char buffer[];       /* Actual buffer storage starts here */
};

/*On the linux side we want to make sure packet data is all set up
  before the packet's existence becomes visible to the PRUs.  There's
  surely a more subtle way to do this but for now we do a full memory
  barrier before changing writePtr or readPtr.*/
#ifdef __KERNEL__
#define SYNC_MEMORY()  __sync_synchronize()
#else
#define SYNC_MEMORY() do { } while (0)
#endif

#define SIZEOF_PACKET_BUFFER_HEADER 32

#define RING_BUFFER_BITS_LRG 13
#define RING_BUFFER_BITS_MED 11
#define RING_BUFFER_BITS_SML 9

#define RING_BUFFER_SIZE_LRG (1u<<RING_BUFFER_BITS_LRG)
#define RING_BUFFER_SIZE_MED (1u<<RING_BUFFER_BITS_MED)
#define RING_BUFFER_SIZE_SML (1u<<RING_BUFFER_BITS_SML)

#define RING_BUFFER_MASK_LRG (RING_BUFFER_SIZE_LRG - 1)
#define RING_BUFFER_MASK_MED (RING_BUFFER_SIZE_MED - 1)
#define RING_BUFFER_MASK_SML (RING_BUFFER_SIZE_SML - 1)

#define PACKET_BUFFER_SIZE_LRG (SIZEOF_PACKET_BUFFER_HEADER + RING_BUFFER_SIZE_LRG)
#define PACKET_BUFFER_SIZE_MED (SIZEOF_PACKET_BUFFER_HEADER + RING_BUFFER_SIZE_MED)
#define PACKET_BUFFER_SIZE_SML (SIZEOF_PACKET_BUFFER_HEADER + RING_BUFFER_SIZE_SML)

typedef unsigned char PacketBufferStorageLRG[PACKET_BUFFER_SIZE_LRG];
typedef unsigned char PacketBufferStorageMED[PACKET_BUFFER_SIZE_MED];
typedef unsigned char PacketBufferStorageSML[PACKET_BUFFER_SIZE_SML];

static inline struct PacketBuffer * PacketBufferFromPacketBufferStorageInline(unsigned char * pbs) {
  return (struct PacketBuffer *) pbs;
}

extern struct PacketBuffer * PacketBufferFromPacketBufferStorage(unsigned char * pbs) ;

static inline void pbInitInline(struct PacketBuffer * pb, unsigned ringBufferBits) {
  unsigned bufsize = 1u<<ringBufferBits;
  unsigned size = bufsize+SIZEOF_PACKET_BUFFER_HEADER;
  memset(pb, 0, size);
  pb->bufferSize = bufsize;
  pb->bufferMask = bufsize - 1;
  
}
extern void pbInit(struct PacketBuffer * pb, unsigned ringBufferBits) ;

static inline unsigned int pbIsEmptyInline(struct PacketBuffer * pb) {
  return  pb->writePtr == pb->readPtr;
}

static inline unsigned int pbUsedBytesInline(struct PacketBuffer * pb) {
  int diff = pb->writePtr - pb->readPtr;
  if (diff < 0) diff += pb->bufferSize;
  return (unsigned int) diff;
}

extern unsigned int pbUsedBytes(struct PacketBuffer * pb) ;

static inline unsigned int pbAvailableBytesInline(struct PacketBuffer * pb) {
  return pb->bufferSize - pbUsedBytesInline(pb) - 1;
}

extern unsigned int pbAvailableBytes(struct PacketBuffer * pb) ;

static inline void pbStartWritingPendingPacketInline(struct PacketBuffer * pb) {
  pb->writeIdx = 0;
}

extern void pbStartWritingPendingPacket(struct PacketBuffer * pb) ;

static inline unsigned int pbWriteByteInPendingPacketInline(struct PacketBuffer *pb, unsigned byteToStore) {
  if (pbAvailableBytes(pb) <= pb->writeIdx) return 0;
  if (pb->writeIdx >= 255) return 0;
  pb->buffer[(pb->writePtr + 1 + pb->writeIdx++) & pb->bufferMask] = byteToStore;
  return 1;
}

extern unsigned int pbWriteByteInPendingPacket(struct PacketBuffer *pb, unsigned byteToStore) ;

static inline unsigned int pbCommitPendingPacketInline(struct PacketBuffer *pb) {
  if (pb->writeIdx == 0) return 0;
  pb->buffer[pb->writePtr] = pb->writeIdx;
  /* Packet becomes visible to reader when writePtr is updated. */
  SYNC_MEMORY();
  pb->writePtr = (pb->writePtr + pb->writeIdx + 1) & pb->bufferMask;
  pbStartWritingPendingPacketInline(pb);
  return 1;
}

extern unsigned int pbCommitPendingPacket(struct PacketBuffer *pb) ;

static inline unsigned int pbGetLengthOfOldestPacketInline(struct PacketBuffer * pb) {
  if (pbUsedBytesInline(pb)==0) return 0;
  return pb->buffer[pb->readPtr];
}

extern unsigned int pbGetLengthOfOldestPacket(struct PacketBuffer * pb) ;

static inline int pbGetTypeOfOldestPacketIfAnyInline(struct PacketBuffer * pb) {
  if (pbUsedBytesInline(pb)==0) return -1;
  return pb->buffer[(pb->readPtr + 1) & pb->bufferMask];
}

extern int pbGetTypeOfOldestPacketIfAny(struct PacketBuffer * pb) ;

static inline unsigned int pbStartReadingOldestPacketInline(struct PacketBuffer * pb) {
  if (pbUsedBytesInline(pb)==0) return 0;
  pb->readIdx = 0;
  return 1;
}

extern inline unsigned int pbStartReadingOldestPacket(struct PacketBuffer * pb) ;

static inline int pbReadByteFromOldestPacketInline(struct PacketBuffer *pb) {
  if (pbUsedBytesInline(pb) < pb->readIdx) return -1;
  return pb->buffer[(pb->readPtr + 1 + pb->readIdx++) & pb->bufferMask];
}

extern int pbReadByteFromOldestPacket(struct PacketBuffer *pb) ;

static inline unsigned int pbDropOldestPacketInline(struct PacketBuffer *pb) {
  if (pbUsedBytesInline(pb) == 0) return 0;
  /* Free space becomes visible to writer when readPtr is updated. */
  SYNC_MEMORY();
  pb->readPtr = (pb->readPtr + pb->buffer[pb->readPtr] + 1) & pb->bufferMask;
  return pbStartReadingOldestPacketInline(pb);
}

extern unsigned int pbDropOldestPacket(struct PacketBuffer *pb) ;

/////////////// CONVENIENCE ROUTINES
extern int pbWritePacketIfPossible(struct PacketBuffer *pb, unsigned char * data, unsigned length) ;

extern int pbReadPacketIfPossible(struct PacketBuffer *pb, unsigned char * data, unsigned length) ;

extern int pbTransferPacketIfPossible(struct PacketBuffer *pbto, struct PacketBuffer *pbfrom) ;

#ifdef __KERNEL__

extern int pbWritePacketIfPossibleFromUser(struct PacketBuffer *pb, void __user * from, unsigned length) ;

extern int pbReadPacketIfPossibleToUser(struct PacketBuffer *pb, void __user * to, unsigned length) ;

#endif


enum PacketBufferErrors {
  PBE_PERM=		 1,	/* Operation not permitted */
  PBE_NOENT=		 2,	/* No such file or directory */
  PBE_SRCH=		 3,	/* No such process */
  PBE_INTR=		 4,	/* Interrupted system call */
  PBE_IO=		 5,	/* I/O error */
  PBE_NXIO=		 6,	/* No such device or address */
  PBE_2BIG=		 7,	/* Argument list too long */
  PBE_NOEXEC=		 8,	/* Exec format error */
  PBE_BADF=		 9,	/* Bad file number */
  PBE_CHILD=		10,	/* No child processes */
  PBE_AGAIN=		11,	/* Try again */
  PBE_NOMEM=		12,	/* Out of memory */
  PBE_ACCES=		13,	/* Permission denied */
  PBE_FAULT=		14,	/* Bad address */
  PBE_NOTBLK=		15,	/* Block device required */
  PBE_BUSY=		16,	/* Device or resource busy */
  PBE_EXIST=		17,	/* File exists */
  PBE_XDEV=		18,	/* Cross-device link */
  PBE_NODEV=		19,	/* No such device */
  PBE_NOTDIR=		20,	/* Not a directory */
  PBE_ISDIR=		21,	/* Is a directory */
  PBE_INVAL=		22,	/* Invalid argument */
  PBE_NFILE=		23,	/* File table overflow */
  PBE_MFILE=		24,	/* Too many open files */
  PBE_NOTTY=		25,	/* Not a typewriter */
  PBE_TXTBSY=		26,	/* Text file busy */
  PBE_FBIG=		27,	/* File too large */
  PBE_NOSPC=		28,	/* No space left on device */
  PBE_SPIPE=		29,	/* Illegal seek */
  PBE_ROFS=		30,	/* Read-only file system */
  PBE_MLINK=		31,	/* Too many links */
  PBE_PIPE=		32,	/* Broken pipe */
  PBE_DOM=		33,	/* Math argument out of domain of func */
  PBE_RANGE=		34,	/* Math result not representable */
};


#endif /* PACKETBUFFER_H */
