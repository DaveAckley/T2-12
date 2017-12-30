#include "Buffers.h"
#include "LinuxIO.h"

#pragma DATA_SECTION(pruDirData, ".asmbuf")
struct PruDirs pruDirData;

unsigned minORBAvailablePruDirs(struct PruDirs * pd)
{
  uint32_t min = orbAvailableBytes(&pd->pruDirBuffers[0].out);
  uint32_t avail;
  avail = orbAvailableBytes(&pd->pruDirBuffers[1].out); if (avail < min) min = avail;
  avail = orbAvailableBytes(&pd->pruDirBuffers[2].out); if (avail < min) min = avail;
  return min;
}

int orbAddPacket(struct OutboundRingBuffer * orb, unsigned char * data, unsigned char len)
{
  unsigned i;
  if (!data || len == 0 || len >= orbAvailableBytes(orb)) {/* Available must strictly exceed len */
    ++orb->packetsRejected;
    return 1;  
  }
  orbStoreByte(orb,len);       /* To have room to stick packet length first */
  for (i = 0; i < len; ++i)    /* Something smarter here should exist someday */
    orbStoreByte(orb,data[i]);
  ++orb->packetsAdded;
  return 0;
}

int orbDropFrontPacket(unsigned prudir) { return orbDropFrontPacketInline(pruDirToORB(prudir)); }

unsigned int orbFrontPacketLen(unsigned prudir) { return orbFrontPacketLenInline(pruDirToORB(prudir)); }

unsigned char orbGetFrontPacketByte(unsigned prudir, unsigned idxInPacket) {
  return orbGetFrontPacketByteInline(pruDirToORB(prudir), idxInPacket);
}

void ipbWriteByte(unsigned prudir, unsigned char idxInPacket, unsigned byteToWrite) {
  struct InboundPacketBuffer * ipb = pruDirToIPB(prudir);
  ipb->buffer[idxInPacket] = byteToWrite;
}

void ipbReportFrameError(unsigned prudir, unsigned char packetLength,
                         unsigned ct0,
                         unsigned ct1,
                         unsigned ct2,
                         unsigned ct3,
                         unsigned ct4,
                         unsigned ct5,
                         unsigned ct6,
                         unsigned ct7) {
  struct InboundPacketBuffer * ipb = pruDirToIPB(prudir);
  if (packetLength < 37) {
    packetLength = 37;
  }
  ipb->buffer[0] = PKT_ROUTED_STD_VALUE|PKT_STD_ERROR_VALUE|dircodeFromPrudir(prudir); /*Fill in our source direction*/  
  ipb->buffer[1] = 'F';
  ipb->buffer[2] = 'R';
  ipb->buffer[3] = 'M';
  *((unsigned *) &ipb->buffer[4]) = ct0;
  *((unsigned *) &ipb->buffer[8]) = ct1;
  *((unsigned *) &ipb->buffer[12]) = ct2;
  *((unsigned *) &ipb->buffer[16]) = ct3;
  *((unsigned *) &ipb->buffer[20]) = ct4;
  *((unsigned *) &ipb->buffer[24]) = ct5;
  *((unsigned *) &ipb->buffer[28]) = ct6;
  *((unsigned *) &ipb->buffer[32]) = ct7;
  ipb->buffer[36] = '!';
  if (CSendPacket(ipb->buffer, packetLength))
    ++ipb->packetsRejected; /* Losing a FRM is baad */
}

void ipbSendPacket(unsigned prudir, unsigned char length) {
  if (length) {
    struct InboundPacketBuffer * ipb = pruDirToIPB(prudir);
    ipb->buffer[0] = (ipb->buffer[0]&~PKT_STD_DIRECTION_MASK)|dircodeFromPrudir(prudir); /*Fill in our source direction*/
    if (CSendPacket(&ipb->buffer[0], length))
      ++ipb->packetsRejected;
    else
      ++ipb->packetsReceived;
  }
}
