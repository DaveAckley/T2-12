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

////////////////////
#define QOSPACKETBUFFERFAST_BUFFER_BITS RING_BUFFER_BITS_MED
typedef PacketBufferStorageLRG QoSPacketBufferFast;

#define QOSPACKETBUFFERSLOW_BUFFER_BITS RING_BUFFER_BITS_MED
typedef PacketBufferStorageMED QoSPacketBufferSlow;

struct QoSPacketBufferPair {
  QoSPacketBufferFast fast;  /* Priority rate queue */
  QoSPacketBufferSlow slow;  /* Bulk rate queue */
};
extern void initQoSPacketBufferPair(struct QoSPacketBufferPair * qpbp, PBID *pbid) ;

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

extern void initSharedStatePerITC(struct SharedStatePerITC * sspi, PBID *pbid) ;

static inline struct PacketBuffer * sspiNextOutboundInline(struct SharedStatePerITC * sspi) {
  return getNextPacketBufferToReadInline(&sspi->outbound);
}

extern struct PacketBuffer * sspiNextOutbound(struct SharedStatePerITC * sspi) ;

static inline struct PacketBuffer * sspiNextInboundInline(struct SharedStatePerITC * sspi) {
  return getNextPacketBufferToReadInline(&sspi->inbound);
}

extern struct PacketBuffer * sspiNextInbound(struct SharedStatePerITC * sspi) ;

////////////////////
#define SHAREDSTATEPERPRUDOWNBOUND_BUFFER_BITS RING_BUFFER_BITS_SML
typedef PacketBufferStorageSML SharedStatePerPruPacketBufferDownbound;

#define SHAREDSTATEPERPRUUPBOUND_BUFFER_BITS RING_BUFFER_BITS_SML
typedef PacketBufferStorageSML SharedStatePerPruPacketBufferUpbound;

struct SharedStatePerPru {
  struct SharedStatePerITC pruDirState[3];
  SharedStatePerPruPacketBufferDownbound downbound;     /* Special packets heading down from host to PRU */
  SharedStatePerPruPacketBufferUpbound upbound;         /* Special packets heading up from PRU to host */
};
extern void initSharedStatePerPru(struct SharedStatePerPru * sspp, PBID *pbid) ;

////////////////////
struct SharedState {
  struct SharedStatePerPru pruState[2];
};

/* set up during startup by external code*/
extern struct SharedState * getSharedStatePhysical(void) ;

/* set up during mmap-ing by external code*/
extern void * sharedStateVirtualBaseAddress;

static inline struct SharedState * getSharedStateVirtualInline(void) {
  return (struct SharedState*) sharedStateVirtualBaseAddress;
}

extern void initSharedState(struct SharedState * ss) ;

static inline struct PacketBuffer * getPacketBufferIfAnyInline(struct SharedState * ss, PBID * sss)
{
  struct SharedStatePerPru * sspp;
  struct SharedStatePerITC * sspi;
  struct QoSPacketBufferPair * qpbp;
  struct PacketBuffer * pb;
  if (!ss || !sss || sss->pru > 1 || sss->prudir > 4) return 0;
  sspp = &ss->pruState[sss->pru];
  if (sss->prudir > 2) 
    return PacketBufferFromPacketBufferStorageInline(sss->inbound ? sspp->upbound : sspp->downbound);
  sspi = &sspp->pruDirState[sss->prudir];
  qpbp = sss->inbound ? &sspi->inbound : &sspi->outbound;
  if (sss->bulk < 0) 
    pb = getNextPacketBufferToRead(qpbp);        
  else
    pb = getPacketBufferForQoS(qpbp, sss->bulk);
  return pb;
}

extern struct PacketBuffer * getPacketBufferIfAny(struct SharedState * ss, PBID * sss) ;

#endif /* SHAREDSTATE_H */
