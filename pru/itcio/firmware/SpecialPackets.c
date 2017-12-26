#include "SpecialPackets.h"
#include "LinuxIO.h"

volatile register uint32_t __R31;
volatile register uint32_t __R30;
volatile register uint32_t __R31;

extern void copyOutScratchPad(uint8_t * packet, uint16_t len);
extern int addfuncasm(int a, int b);

unsigned processSpecialPacket(uint8_t * packet, uint16_t len)
{
  unsigned i;
  if (len == 0) return 0; /* or assert? */
  switch (packet[0]) {

  /* PACKET TYPE: '*' Wildcard debug, content non-standardized, can change at will */
  case '*': {                        
    if (len < 4) fillFail("[PKLEN]",packet,len);
    else {
      int32_t a = packet[1];
      int32_t b = packet[2];
      int32_t ret = addfuncasm(a,b);
      packet[3] = (uint8_t) ret;
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

  default:
    {
      fillFail("[PKTYP]",packet,len);
      break;
    }
  }
  return 1;
}

