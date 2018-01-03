#include "SharedState.h"

void initSharedStateSelector(struct SharedStateSelector * sss)
{
  initSharedStateSelectorInline(sss);
}

struct PacketBuffer * getPacketBufferIfAny(struct SharedState * ss, struct SharedStateSelector * sss)
{
  return getPacketBufferIfAnyInline(ss, sss);
}

void initSharedState(struct SharedState * ss)
{
  unsigned i;
  for (i = 0; i < 2; ++i)
    initSharedStatePerPru(&ss->pruState[i]);
}

void initQoSPacketBufferPair(struct QoSPacketBufferPair * qpbp)
{
  pbInit((struct PacketBuffer*) &qpbp->fast, RING_BUFFER_BITS_MED);
  pbInit((struct PacketBuffer*) &qpbp->slow, RING_BUFFER_BITS_MED);
}

void initSharedStatePerITC(struct SharedStatePerITC * sspi)
{
  initQoSPacketBufferPair(&sspi->outbound);
  initQoSPacketBufferPair(&sspi->inbound);
}

void initSharedStatePerPru(struct SharedStatePerPru * sspp)
{
  unsigned i;
  for (i = 0; i < 3; ++i)
    initSharedStatePerITC(&sspp->pruDirState[i]);
}

struct SharedState * getSharedStatePhysical()
{
  return getSharedStatePhysicalInline();
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
