#include "Buffers.h"
#include "LinuxIO.h"

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

void ipbWriteByte(unsigned prudir, unsigned char idxInPacket, unsigned char byteToWrite) {
  struct InboundPacketBuffer * ipb = pruDirToIPB(prudir);
  ipb->buffer[idxInPacket] = byteToWrite;
}

void ipbReportFrameError(unsigned prudir, unsigned char packetLength) {
  struct InboundPacketBuffer * ipb = pruDirToIPB(prudir);
  if (packetLength < 1) {
    packetLength = 1;
    ipb->buffer[0] = PKT_ROUTED_STD_VALUE|PKT_STD_ERROR_VALUE;
  } else {
    ipb->buffer[0] |= PKT_STD_ERROR_VALUE;
  }
  ipb->buffer[0] = (ipb->buffer[0]&~PKT_STD_DIRECTION_MASK)|prudir; /*Fill in our source direction*/  
  CSendPacket(ipb->buffer, packetLength);
}

int ipbSendPacket(unsigned prudir, unsigned char length) {
  if (length) {
    struct InboundPacketBuffer * ipb = pruDirToIPB(prudir);
    ipb->buffer[0] = (ipb->buffer[0]&~PKT_STD_DIRECTION_MASK)|prudir; /*Fill in our source direction*/
    return CSendPacket(ipb->buffer, length);
  }
  return 0;
}
