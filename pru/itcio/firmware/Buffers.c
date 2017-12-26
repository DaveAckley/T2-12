#include "Buffers.h"

#pragma DATA_SECTION(pruDirData, ".asmbuf")
struct PruDirs pruDirData;

int orbAddPacket(struct OutboundRingBuffer * orb, unsigned char * data, unsigned char len)
{
  unsigned i;
  if (!data || len >= orbAvailableBytes(orb)) return 1;  /* Available must strictly exceed len */
  orbStoreByte(orb,len);       /* To have room to stick packet length first */
  for (i = 0; i < len; ++i)    /* Something smarter here should exist someday */
    orbStoreByte(orb,data[i]);
  return 0;
}

int orbDropFrontPacket(unsigned prudir) { return orbDropFrontPacketInline(pruDirToORB(prudir)); }

unsigned int orbFrontPacketLen(unsigned prudir) { return orbFrontPacketLenInline(pruDirToORB(prudir)); }

unsigned char orbGetFrontPacketByte(unsigned prudir, unsigned idxInPacket) {
  return orbGetFrontPacketByteInline(pruDirToORB(prudir), idxInPacket);
}
