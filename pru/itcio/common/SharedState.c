#include "SharedState.h"

void initSharedStateSelector(struct SharedStateSelector * sss)
{
  initSharedStateSelectorInline(sss);
}

struct PacketBuffer * getPacketBufferIfAny(struct SharedState * ss, struct SharedStateSelector * sss)
{
  return getPacketBufferIfAnyInline(ss, sss);
}

char * sharedStateSelectorCode(struct SharedStateSelector * sss, char * buf)
{
  buf[0] = sss->pru+'0';
  buf[1] = sss->prudir+'a';
  buf[2] = sss->inbound ? 'i' : 'o';
  buf[3] = sss->bulk ? 's' : 'f';
  return &buf[4];
}

void initSharedState(struct SharedState * ss)
{
  unsigned i;
  for (i = 0; i < 2; ++i)
    initSharedStatePerPru(&ss->pruState[i]);
}

void initQoSPacketBufferPair(struct QoSPacketBufferPair * qpbp)
{
  pbInit((struct PacketBuffer*) &qpbp->fast, QOSPACKETBUFFERFAST_BUFFER_BITS);
  pbInit((struct PacketBuffer*) &qpbp->slow, QOSPACKETBUFFERSLOW_BUFFER_BITS);
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
  pbInit((struct PacketBuffer*) &sspp->downbound, SHAREDSTATEPERPRUDOWNBOUND_BUFFER_BITS);
  pbInit((struct PacketBuffer*) &sspp->upbound, SHAREDSTATEPERPRUUPBOUND_BUFFER_BITS);
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
