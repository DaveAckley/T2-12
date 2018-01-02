#include "SpecialPackets.h"
#include "LinuxIO.h"
#include "Buffers.h"

volatile register uint32_t __R31;
volatile register uint32_t __R30;

#include "Threads.h"
#include "SharedState.h"

typedef struct iostream {
  uint8_t * data;
  uint16_t length;
  uint16_t pos;
} IOS;

void initIOS(IOS * io, uint8_t * data, uint32_t len) {
  io->data = data;
  io->length = len;
  io->pos = 0;
}

void rewindIOS(IOS * io) { io->pos = 0; }

int32_t seekIOS(IOS * io, int32_t delta) {
  int32_t newpos = io->pos + delta;
  if (newpos >= 0 && newpos <= io->length) {
    io->pos = newpos;
    return 1;
  }
  return 0;
}

int32_t readIOS(IOS * io) {
  if (io->pos >= io->length) return -1;
  return io->data[io->pos++];
}

int32_t writeIOS(IOS * io, uint8_t newbyte) {
  if (io->pos >= io->length) return 0;
  io->data[io->pos++] = newbyte;
  return 1;
}

uint8_t makeHex(uint8_t fourbits) {
  return fourbits < 10 ? ('0' + fourbits) : ('a' - 10 + fourbits);
}

int32_t writeHexIOS(IOS * io, uint8_t newbyte) {
  return
    writeIOS(io,makeHex((newbyte>>4)&0xf)) &&
    writeIOS(io,makeHex((newbyte>>0)&0xf));
}

int32_t writeFormatIOS(IOS * io, uint8_t newbyte, uint8_t format) {
  if (format == 'h') return writeHexIOS(io, newbyte);
  return writeIOS(io,newbyte);
}

int32_t write16IOS(IOS * io, uint16_t word) {
  return
    writeIOS(io, word&0xff) &&
    writeIOS(io, (word>>8)&0xff);
}

int32_t writeHex16IOS(IOS * io, uint16_t val) {
  return
    writeHexIOS(io,(val>>8)&0xff) &&
    writeHexIOS(io,(val>>0)&0xff);
}

int32_t writeFormat16IOS(IOS * io, uint16_t val, uint8_t format) {
  if (format == 'h') return writeHex16IOS(io, val);
  return write16IOS(io,val);
}

int32_t write32IOS(IOS * io, uint32_t word) {
  return
    write16IOS(io, word&0xffff) &&
    write16IOS(io, (word>>16)&0xffff);
}

int32_t writeHex32IOS(IOS * io, uint32_t word) {
  return
    writeHex16IOS(io, (word>>16)&0xffff) &&
    writeHex16IOS(io, word&0xffff);
}

int32_t writeFormat32IOS(IOS * io, uint32_t val, uint8_t format) {
  if (format == 'h') return writeHex32IOS(io, val);
  return write32IOS(io,val);
}

int32_t writePrevIOS(IOS *io, uint8_t newbyte) {
  if (seekIOS(io,-1)) {
    writeIOS(io,newbyte);
    return 1;
  }
  return 0;
}


int32_t peekIOS(IOS * io) {
  if (io->pos >= io->length) return -1;
  return io->data[io->pos];
}

uint16_t cursorIOS(IOS *io) { return io->pos; }

void processPacketEnginePacket(uint8_t * argspace, uint16_t arglen) {
  IOS iostream;
  IOS * ios = &iostream;
  int32_t ch;
  uint32_t prudir = 0;
  int32_t doreset = 0;
  uint8_t format = 'r';
  struct InboundPacketBuffer * ipb = pruDirToIPB(prudir);
  struct OutboundRingBuffer * orb = pruDirToORB(prudir);

  initIOS(ios, argspace, arglen);

  while ((ch = readIOS(ios)) >= 0) {
    doreset = 0;
    switch (ch) {
    case 'd': {                 /* d: set prudir */
      ch = readIOS(ios);
      if (ch >= '0' && ch <= '2') {
        prudir = ch-'0';
        ipb = pruDirToIPB(prudir);
        orb = pruDirToORB(prudir);
      }
      else
        return;
      break;
    }
    case '?': {                 /* ?: Query arrival at this position */
      writePrevIOS(ios,'.');    /* .: We got here */
      break;
    }
    case 'f': {
      ch = readIOS(ios);
      if (ch == 'h' || ch == 'r') format = ch;
      else return;
      break;
    }
    case ' ': 
    case '#':                  /* # or ' ': legal skip; leave unmodified */
      break;

    case 'p':{                 /* p: Report pru# in next byte */
      writeIOS(ios,makeHex(ON_PRU));
      break;
    }

    case 'I': doreset = 1;      /* I: Report and reset inbound stats for prudir */
      // FALL THROUGH
    case 'i': {                 /* i: Report inbound stats for prudir */
      writeFormat32IOS(ios,ipb->packetsReceived,format);
      writeIOS(ios,'x');
      writeFormat32IOS(ios,ipb->packetsRejected,format);
      if (doreset) {
        ipb->packetsReceived = 0;
        ipb->packetsRejected = 0;
      }
      break;
    }
    case 'O': doreset = 1;      /* O: Report and reset outbount stats for prudir */
      // FALL THROUGH
    case 'o': {                 /* o: Report outbound stats for prudir */
      writeFormat32IOS(ios,orb->packetsAdded,format);
      writeIOS(ios,'/');
      writeFormat32IOS(ios,orb->packetsRemoved,format);
      writeIOS(ios,'x');
      writeFormat32IOS(ios,orb->packetsRejected,format);
      if (doreset) {
        orb->packetsAdded = 0;
        orb->packetsRemoved = 0;
        orb->packetsRejected = 0;
      }
      break;
    }

    default:                    /* Anything unknown stops the show */
      return;
    }
  }
}

unsigned processSpecialPacket(uint8_t * packet, uint16_t len)
{
  unsigned i;
  if (len == 0) return 0; /* or assert? */
  switch (packet[0]) {

  /* PACKET TYPE: '*' Wildcard debug, content non-standardized, can change at will */
  case '*': {                        
    if (len < 10) fillFail("[PKLEN]",packet,len);
    else {
      struct SharedState * ss = getSharedStatePhysical();
      struct SharedStatePerPru * sspp = &ss->pruState[ON_PRU];
      *((uint32_t *) &packet[3]) = *(uint32_t*) sspp;
    }
    break;
  }


  /* PACKET TYPE: write 'B'it of R30 (return old value) */
  case 'B': {                        
    if (len < 3) fillFail("[PKLEN]",packet,len);
    else {
      uint32_t bitnum = packet[1];
      uint32_t mask = 1<<bitnum;
      uint32_t oldval = (__R30 & mask) ? 1 : 0;
      uint32_t newval = packet[2];
      if (bitnum > 31 || newval > 1) fillFail("[INVAL]",packet,len);
      else {
        if (newval) __R30 |= mask;
        else __R30 &= ~mask;
        packet[2] = oldval;
      }
    }
    break;
  }

  /* PACKET TYPE: 'W'rite R30 (and then R31) */
  case 'W': {                        
    uint32_t tmp = 0;
    uint32_t tlen = len;
    if (tlen > 5) tlen = 5;
    for (i = 1; i < tlen; ++i) {
      tmp |= packet[i]<<((i-1)<<3);
    }
    __R30 = tmp;
  }
  /* FALL THROUGH INTO CASE 'R' */

  /* PACKET TYPE: 'R'ead R31 (and R30 if room) */
  case 'R': {                        
    uint32_t r31 = __R31;
    uint32_t r30 = __R30;
    for (i = 1; i < len; ++i) {
      if (i < 5) {
        packet[i] = r31&0xff;
        r31 >>=8;
      } else if (i == 5) continue; /* leave [5] untouched; itc_pin_read_handler checks it */
      else if (i < 10) {
        packet[i] = r30&0xff;
        r30 >>=8;
      } else break;
    }
    break;
  }

  /* PACKET TYPE: 'S'cratchpad memory read */
  case 'S': {                        
    if (len > 4)
      copyOutScratchPad(&packet[0], len);
    else
      fillFail("[PKLEN]",packet,len);
    break;
  }

  /* PACKET TYPE: 'P'acket engine access */
  case 'P': {                        
    processPacketEnginePacket(&packet[1], len-1);
    break;
  }
    
  default:
    {
      fillFail("[PKTYP]",packet,len);
      break;
    }
  }
  return 1;
}

