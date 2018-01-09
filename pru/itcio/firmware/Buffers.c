#include "Buffers.h"
#include "LinuxIO.h"
#include "SharedState.h"

#pragma DATA_SECTION(pruDirData, ".asmbuf")
struct PruDirs pruDirData;

/*
void ppbWriteInboundByte(unsigned prudir, unsigned char idxInPacket, unsigned byteToWrite) {
  struct PRUPacketBuffer * ppb = pruDirToInPPB(prudir);
  ppb->buffer[idxInPacket] = byteToWrite;
}

int ppbReadOutboundByte(unsigned prudir, unsigned char idxInPacket) {
  struct PRUPacketBuffer * ppb = pruDirToOutPPB(prudir);
  return ppb->buffer[idxInPacket];
}
*/

void ppbReportFrameError(unsigned prudir, unsigned char packetLength,
                         unsigned ct0,
                         unsigned ct1,
                         unsigned ct2,
                         unsigned ct3,
                         unsigned ct4,
                         unsigned ct5,
                         unsigned ct6,
                         unsigned ct7) {
  struct PRUDirBuffers * pdb = pruDirToBuffers(prudir);
  if (packetLength < 37) {
    packetLength = 37;
  }
  pdb->inbuffer[0] = PKT_ROUTED_STD_VALUE|PKT_STD_ERROR_VALUE|dircodeFromPrudir(prudir); /*Fill in our source direction*/  
  pdb->inbuffer[1] = 'F';
  pdb->inbuffer[2] = 'R';
  pdb->inbuffer[3] = 'M';
  *((unsigned *) &pdb->inbuffer[4]) = ct0;
  *((unsigned *) &pdb->inbuffer[8]) = ct1;
  *((unsigned *) &pdb->inbuffer[12]) = ct2;
  *((unsigned *) &pdb->inbuffer[16]) = ct3;
  *((unsigned *) &pdb->inbuffer[20]) = ct4;
  *((unsigned *) &pdb->inbuffer[24]) = ct5;
  *((unsigned *) &pdb->inbuffer[28]) = ct6;
  *((unsigned *) &pdb->inbuffer[32]) = ct7;
  pdb->inbuffer[36] = '!';
  if (ppbSendInboundPacket(prudir, packetLength))
    ++pdb->instats.packetDrops; /* Losing a FRM is baad */
}

int ppbSendInboundPacket(unsigned prudir, unsigned char length) {
  int ret = 0;
  struct PRUDirBuffers * pdb = pruDirToBuffers(prudir);
  struct PacketBuffer * pb;
  PBID sss;
  sss.pru = ON_PRU;
  sss.prudir = prudir;
  sss.inbound = 1;

  if (length > 0) {

    sss.bulk = ( (pdb->inbuffer[0]&PKT_BULK_STD_MASK) == PKT_BULK_STD_VALUE );
    pdb->inbuffer[0] = (pdb->inbuffer[0]&~PKT_STD_DIRECTION_MASK)|dircodeFromPrudir(prudir); /*Fill in our source direction*/
    pb = getPacketBufferIfAny(getSharedStatePhysical(), &sss); /*'IfAny' only applies if sss.bulk<0*/

    // NOTE: Only kicking ARM on empty -> non-empty transitions is
    // racy because itc_pkt.ko may drain the last packet, and stop
    // checking the buffer, after we do this check but before the
    // ensuing pbWritePacket commits.
    //
    // A safer thing would be to kick after every packet but that's a
    // bit expensive -- and even with that I'm worried linux could run
    // way long and miss an interrupt, and then we'd still be dead.
    //
    // So what we're doing is accept the race risk of kicking just on
    // empty -> non-empty, and have itc_pkt.ko time out and poll all
    // buffers reasonably often as a backstop.

    if (pbIsEmptyInline(pb))
      pdb->instats.flags |= NEED_KICK;

    if (pbWritePacketIfPossible(pb, pdb->inbuffer, length)) {
      ++pdb->instats.packetStalls;
      ret = -PBE_BUSY;
    } else 
      ++pdb->instats.packetTransfers;

    if (pdb->instats.flags & NEED_KICK) {
      if (CSendPacket((uint8_t*) &sss,sizeof(sss))==0)
        pdb->instats.flags &= ~NEED_KICK;
    }
  }

  return ret;
}

int ppbReceiveOutboundPacket(unsigned prudir) {
  int len;
  struct PRUDirBuffers * pdb = pruDirToBuffers(prudir);
  struct PacketBuffer * pb;
  PBID sss;
  sss.pru = ON_PRU;
  sss.prudir = prudir;
  sss.inbound = 0;
  sss.bulk = -1;
  pb = getPacketBufferIfAny(getSharedStatePhysical(), &sss);
  if (!pb) return 0;
  if (pbIsEmptyInline(pb)) return 0;  /*but shouldn't happen with sss.bulk<0*/

  len = pbReadPacketIfPossible(pb, &pdb->outbuffer[0], MAX_PACKET_SIZE);
  if (len <= 0) return 0;       /* len < 0 "can't happen" */
  ++pdb->outstats.packetTransfers;
  return len;
}
