#include "SharedState.h"

struct PacketBuffer * getPacketBufferIfAny(struct SharedState * ss, PBID * sss)
{
  return getPacketBufferIfAnyInline(ss, sss);
}

void initSharedState(struct SharedState * ss)
{
  unsigned i;
  PBID sss;
  for (i = 0; i < 2; ++i) {
    sss.pru = i;
    initSharedStatePerPru(&ss->pruState[i],&sss);
  }
}

void initQoSPacketBufferPair(struct QoSPacketBufferPair * qpbp, PBID *sss)
{
  sss->bulk = 0; pbInit((struct PacketBuffer*) &qpbp->fast, QOSPACKETBUFFERFAST_BUFFER_BITS, sss);
  sss->bulk = 1; pbInit((struct PacketBuffer*) &qpbp->slow, QOSPACKETBUFFERSLOW_BUFFER_BITS, sss);
}

void initSharedStatePerITC(struct SharedStatePerITC * sspi, PBID *sss)
{
  sss->inbound = 0; initQoSPacketBufferPair(&sspi->outbound, sss);
  sss->inbound = 1; initQoSPacketBufferPair(&sspi->inbound, sss);
}

void initSharedStatePerPru(struct SharedStatePerPru * sspp, PBID *sss)
{
  unsigned i;
  for (i = 0; i < 3; ++i) {
    sss->prudir = i;
    initSharedStatePerITC(&sspp->pruDirState[i], sss);
  }
  sss->prudir = 4;
  sss->inbound = 0;
  pbInit((struct PacketBuffer*) &sspp->downbound, SHAREDSTATEPERPRUDOWNBOUND_BUFFER_BITS, sss);
  sss->inbound = 1;
  pbInit((struct PacketBuffer*) &sspp->upbound, SHAREDSTATEPERPRUUPBOUND_BUFFER_BITS, sss);
}

struct PacketBuffer * getNextPacketBufferToRead(struct QoSPacketBufferPair * qpbp)
{
  return getNextPacketBufferToReadInline(qpbp);
}

struct PacketBuffer * getPacketBufferForQoS(struct QoSPacketBufferPair * qpbp, unsigned bulk)
{
  return getPacketBufferForQoSInline(qpbp, bulk);
}

struct PacketBuffer * sspiNextOutbound(struct SharedStatePerITC * sspi)
{
  return sspiNextOutboundInline(sspi) ;
}

struct PacketBuffer * sspiNextInbound(struct SharedStatePerITC * sspi)
{
  return sspiNextInboundInline(sspi) ;
}

#ifdef __KERNEL__
#include <linux/module.h>
MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("Dave Ackley <ackley@ackleyshack.com>");
MODULE_DESCRIPTION("T2 PRU<->ARM shared state management");
#endif
