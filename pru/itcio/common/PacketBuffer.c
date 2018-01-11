#include "PacketBuffer.h"

struct PacketBuffer * PacketBufferFromPacketBufferStorage(unsigned char * pbs)
{
  return PacketBufferFromPacketBufferStorageInline(pbs);
}

void initPBID(PBID * sss)
{
  initPBIDInline(sss);
}

char * PBToString(struct PacketBuffer * pb)
{
  static char buf[5];
  return PBIDToString(&pb->pbid, buf);
}

char * PBIDToString(PBID * sss, char * buf)
{
  buf[0] = sss->pru+'0';
  buf[1] = sss->prudir+'a';
  buf[2] = sss->inbound ? 'i' : 'o';
  buf[3] = (sss->bulk < 0) ? '?' : (sss->bulk ? 's' : 'f');
  buf[4] = '\0';
  return buf;
}

void pbInit(struct PacketBuffer * pb, unsigned ringBufferBits, PBID * pbid)
{
  unsigned bufsize = 1u<<ringBufferBits;
  unsigned size = bufsize+SIZEOF_PACKET_BUFFER_HEADER;
  memset(pb, 0, size);
  pb->bufferSize = bufsize;
  pb->bufferMask = bufsize - 1;
  pb->pbid = *pbid;
}

unsigned int pbUsedBytes(struct PacketBuffer * pb)
{
  return pbUsedBytesInline(pb);
}

unsigned int pbAvailableBytes(struct PacketBuffer * pb)
{
  return pbAvailableBytesInline(pb);
}

void pbStartWritingPendingPacket(struct PacketBuffer * pb)
{
  pbStartWritingPendingPacketInline(pb);
}

unsigned int pbWriteByteInPendingPacket(struct PacketBuffer *pb, unsigned byteToStore)
{
  return pbWriteByteInPendingPacketInline(pb, byteToStore);
}

unsigned int pbCommitPendingPacket(struct PacketBuffer *pb)
{
  return pbCommitPendingPacketInline(pb);
}

unsigned int pbGetLengthOfOldestPacket(struct PacketBuffer * pb)
{
  return pbGetLengthOfOldestPacketInline(pb);
}

int pbGetTypeOfOldestPacketIfAny(struct PacketBuffer * pb)
{
  return pbGetTypeOfOldestPacketIfAnyInline(pb);
}

unsigned int pbStartReadingOldestPacket(struct PacketBuffer * pb)
{
  return pbStartReadingOldestPacketInline(pb);
}

int pbReadByteFromOldestPacket(struct PacketBuffer *pb)
{
  return pbReadByteFromOldestPacketInline(pb);
}

unsigned int pbDropOldestPacket(struct PacketBuffer *pb)
{
  return pbDropOldestPacketInline(pb);
}

static inline unsigned min(unsigned a, unsigned b) { if (a<b) return a; return b; }

int pbWritePacketIfPossible(struct PacketBuffer *pb, unsigned char * data, unsigned length)
{
  int hadUsed;
  unsigned l, w;
  if (!pb || !data || length == 0) return -PBE_INVAL;
  if (length > 255) return -PBE_FBIG;
  if (pbAvailableBytes(pb) < length + 1) return -PBE_NOMEM;
  hadUsed = pbUsedBytesInline(pb);
  w = (pb->writePtr + 1) & pb->bufferMask; /*where we start writing packet data*/
  l = min(length, pb->bufferSize - w);     /*amt of packet before wrap*/
  memcpy(&pb->buffer[w], data, l);         /*transfer that part, if any*/
  memcpy(&pb->buffer[0], data+l, length-l); /*transfer the rest, if any*/
  pb->writeIdx = length;                    /*set up to stash length separately, sigh*/
  pbCommitPendingPacket(pb);                /*move writeptr; make packet visible*/
  return hadUsed==0; /*nonzero if had been empty */
}

int pbReadPacketIfPossible(struct PacketBuffer *pb, unsigned char * data, unsigned length)
{
  unsigned plen, l, r;
  int ret;
  if (!pb || !data || length == 0) return -PBE_INVAL;
  plen = pbGetLengthOfOldestPacket(pb);
  if (plen == 0) return 0;
  if (plen > length) {                    /* If packet longer than buffer */
    plen = length;                        /* Just read what we can */
    ret = -PBE_FBIG;                      /* But return an error code */
  } else ret = plen;
  r = (pb->readPtr + 1) & pb->bufferMask; /*where we start reading*/
  l = min(plen, pb->bufferSize - r);      /*amt of packet before wrap*/
  memcpy(data, &pb->buffer[r], l);        /*transfer that part, if any*/
  memcpy(data+l, &pb->buffer[0], plen-l); /*transfer the rest, if any*/
  pbDropOldestPacket(pb);
  return ret;
}

#ifdef __KERNEL__
#include <asm/uaccess.h>           /* Required for the copy to user function */
int pbWritePacketIfPossibleFromUser(struct PacketBuffer *pb, void __user * from, unsigned length)
{
  u8 __user * cfrom = (u8*) from;
  unsigned l, w;
  if (!pb || !from || length == 0) return -PBE_INVAL;
  if (length > 255) return -PBE_FBIG;
  if (pbAvailableBytes(pb) < length + 1) return -PBE_NOMEM;

  w = (pb->writePtr + 1) & pb->bufferMask; /*where we start writing packet data*/
  l = min(length, pb->bufferSize - w);     /*amt of packet before wrap*/
  if (copy_from_user(&pb->buffer[w], cfrom, l) || /*transfer part before wrap if any*/
      copy_from_user(&pb->buffer[0], cfrom+l, length-l)) { /*and part after wrap if any*/
    printk(KERN_ERR "pb: copy_from_user failed\n");
    return -PBE_FAULT;
  }
  pb->writeIdx = length;        /* set up to stash length */
  pbCommitPendingPacket(pb);
  return 0;
}

int pbReadPacketIfPossibleToUser(struct PacketBuffer *pb, void __user * to, unsigned length)
{
  unsigned plen, l, r;
  int error = 0;
  u8 __user * cto = (u8*) to;
  if (!pb || !to || length == 0) return -PBE_INVAL;
  plen = pbGetLengthOfOldestPacket(pb);
  if (plen == 0) return 0;
  if (plen > length) error = -PBE_FBIG;
  else {
    r = (pb->readPtr + 1) & pb->bufferMask; /*where we start reading*/
    l = min(plen, pb->bufferSize - r);      /*amt of packet before wrap*/
    if (copy_to_user(cto, &pb->buffer[r], l) || /*transfer part before wrap if any*/
        copy_to_user(cto+l, &pb->buffer[0], plen-l)) {/*and part after wrap if any*/
      printk(KERN_ERR "pb: copy_to_user failed\n");
      error = -PBE_FAULT;
    }
  }
  pbDropOldestPacket(pb);
  if (error < 0) return error;
  return plen;
}
#endif

int pbTransferPacketIfPossible(struct PacketBuffer *pbto, struct PacketBuffer *pbfrom)
{
  unsigned tlen;
  if (!pbto || !pbfrom) return -PBE_INVAL;
  tlen = pbGetLengthOfOldestPacket(pbfrom);
  if (tlen == 0) return -PBE_AGAIN;
  if (pbAvailableBytes(pbto) < tlen + 1) return -PBE_NOMEM;
  pbStartReadingOldestPacket(pbfrom);
  pbStartWritingPendingPacket(pbto);
  while (tlen-- > 0)
    pbWriteByteInPendingPacketInline(pbto,
                                     pbReadByteFromOldestPacketInline(pbfrom));
  pbCommitPendingPacket(pbto);
  pbDropOldestPacket(pbfrom);
  return 0;
}


#ifdef __KERNEL__
#include <linux/module.h>
MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("Dave Ackley <ackley@ackleyshack.com>");
MODULE_DESCRIPTION("T2 intertile packet buffers");
#endif
