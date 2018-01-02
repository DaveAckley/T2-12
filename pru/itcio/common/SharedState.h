#ifndef SHAREDSTATE_H                /* -*- C -*- */
#define SHAREDSTATE_H

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

#include "PacketBuffer.h"

#define SHARED_PHYSICAL_BASE_ADDRESS 0xa0000000UL

////////////////////
struct QoSPacketBufferPair {
  PacketBufferStorageMED fast;  /* Priority rate queue */
  PacketBufferStorageMED slow;  /* Bulk rate queue */
};

static inline struct PacketBuffer * getPacketBufferForQoSInline(struct QoSPacketBufferPair * qpbp, unsigned bulk) {
  return
    bulk ?
    PacketBufferFromPacketBufferStorageInline(qpbp->slow) :
    PacketBufferFromPacketBufferStorageInline(qpbp->fast);
}

extern struct PacketBuffer * getPacketBufferForQoS(struct QoSPacketBufferPair * qpbp, unsigned bulk) ;

static inline struct PacketBuffer * getNextPacketBufferToReadInline(struct QoSPacketBufferPair * qpbp) {
  struct PacketBuffer * pb;

  pb = PacketBufferFromPacketBufferStorageInline(qpbp->fast);
  if (pbGetLengthOfOldestPacketInline(pb) > 0) return pb;

  pb = PacketBufferFromPacketBufferStorageInline(qpbp->slow);
  if (pbGetLengthOfOldestPacketInline(pb) > 0) return pb;

  return 0;
}

extern struct PacketBuffer * getNextPacketBufferToRead(struct QoSPacketBufferPair * qpbp) ;


////////////////////
struct SharedStatePerITC {
  struct QoSPacketBufferPair outbound;  /* Packets outbound from host to ITC and beyond */
  struct QoSPacketBufferPair inbound;   /* Packets inbound to host from ITC and beyond */
};

static inline struct PacketBuffer * sspiNextOutboundInline(struct SharedStatePerITC * sspi) {
  return getNextPacketBufferToReadInline(&sspi->outbound);
}

extern struct PacketBuffer * sspiNextOutbound(struct SharedStatePerITC * sspi) ;

static inline struct PacketBuffer * sspiNextInboundInline(struct SharedStatePerITC * sspi) {
  return getNextPacketBufferToReadInline(&sspi->inbound);
}

extern struct PacketBuffer * sspiNextInbound(struct SharedStatePerITC * sspi) ;

////////////////////
struct SharedStatePerPru {
  struct SharedStatePerITC pruDirState[3];
};


////////////////////
struct SharedState {
  struct SharedStatePerPru pruState[2];
};

static inline struct SharedState * getSharedStatePhysicalInline() {
  return (struct SharedState*) SHARED_PHYSICAL_BASE_ADDRESS;
}

extern struct SharedState * getSharedStatePhysical() ;

/* set up during mmap-ing by external code*/
extern void * sharedStateVirtualBaseAddress;

static inline struct SharedState * getSharedStateVirtualInline() {
  return (struct SharedState*) sharedStateVirtualBaseAddress;
}

static inline void initSharedStateInline(struct SharedState * ss) {
  memset(ss, 0, sizeof(*ss));
}

extern void initSharedState(struct SharedState * ss) ;

#endif /* SHAREDSTATE_H */
