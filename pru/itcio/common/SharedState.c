#include "SharedState.h"

void initSharedState(struct SharedState * ss)
{
  return initSharedStateInline(ss);
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
