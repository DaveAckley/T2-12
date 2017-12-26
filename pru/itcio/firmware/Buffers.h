#ifndef BUFFERS_H                /* -*- C -*- */
#define BUFFERS_H

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

extern int orbAddPacket(struct OutboundRingBuffer * orb, unsigned char * data, unsigned char len) ;

inline unsigned int orbFrontPacketLenInline(struct OutboundRingBuffer * orb) {
  if (orbUsedBytes(orb) == 0) return 0;
  return orb->buffer[orb->readPtr];
}

extern unsigned int orbFrontPacketLen(struct OutboundRingBuffer * orb) ;

inline int orbDropFrontPacketInline(struct OutboundRingBuffer * orb) {
  unsigned int len = orbFrontPacketLenInline(orb);
  if (len == 0) return 0;
  orb->readPtr = (orb->readPtr + len + 1) & RING_BUFFER_MASK;
  return 1;
}

extern int orbDropFrontPacket(struct OutboundRingBuffer * orb) ;

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

extern unsigned char orbGetFrontPacketByteInline(struct OutboundRingBuffer * orb, unsigned idxInPacket) ;

#define MAX_PACKET_SIZE 255

struct InboundPacketBuffer {
  unsigned char written;
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

#endif /* BUFFERS_H */
