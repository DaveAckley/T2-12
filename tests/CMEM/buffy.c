/*
 * buffy.c: Demo spike to explore userspace<->PRU communication via cmem
 *
 * Dave Ackley
 *
 * Based on 'devmem2 Simple program to read/write from/to any location in memory.'
 *
 *  Copyright (C) 2000, Jan-Derk Bakker (J.D.Bakker@its.tudelft.nl)
 *
 *
 * This software has been developed for the LART computing board
 * (http://www.lart.tudelft.nl/). The development has been sponsored by
 * the Mobile MultiMedia Communications (http://www.mmc.tudelft.nl/)
 * and Ubiquitous Communications (http://www.ubicom.tudelft.nl/)
 * projects.
 *
 * The author can be reached at:
 *
 *  Jan-Derk Bakker
 *  Information and Communication Theory Group
 *  Faculty of Information Technology and Systems
 *  Delft University of Technology
 *  P.O. Box 5031
 *  2600 GA Delft
 *  The Netherlands
 *
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *
 */

#include <time.h> /*for time*/
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <fcntl.h>
#include <ctype.h>
#include <termios.h>
#include <sys/types.h>
#include <sys/mman.h>

#include "SharedState.h"

  
#define FATAL do { fprintf(stderr, "Error at line %d, file %s (%d) [%s]\n", \
                           __LINE__, __FILE__, errno, strerror(errno)); exit(1); } while(0)
 
#define MAP_SIZE (1UL<<16)
#define MAP_MASK (MAP_SIZE - 1)

#define PAGE_SIZE (1UL<<15)
#define PAGE_MASK (PAGE_SIZE - 1)

void * sharedStateVirtualBaseAddress;

static void printSharedStateSelector(struct SharedStateSelector * sss)
{
  printf("P%dD%dI%dB%c", sss->pru, sss->prudir, sss->inbound,
         sss->bulk < 0 ? 'p' : (sss->bulk? '1' : '0'));
}

int main(int argc, char **argv) {
  int tag;
  int fd;
  /*  off_t target = 0xa0000000UL; */
  off_t target = (off_t) getSharedStatePhysical(); /*0x87f00000UL;*/

  struct SharedState * ss;
  struct SharedStateSelector sss, sss2;
  initSharedStateSelector(&sss);
  initSharedStateSelector(&sss2);

  srandom(time(0));

  tag = random()&0xffff;

  if((fd = open("/dev/mem", O_RDWR | O_SYNC)) == -1) FATAL;
  printf("/dev/mem opened.\n"); 
  fflush(stdout);
    
  /* Map the whole shebabng */
  sharedStateVirtualBaseAddress = mmap(0, MAP_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, target & ~PAGE_MASK);
  if(sharedStateVirtualBaseAddress == (void *) -1) FATAL;
  printf("Memory mapped at address %p. (tag=%04x)\n", sharedStateVirtualBaseAddress, tag); 
  fflush(stdout);
    
  ss = getSharedStateVirtualInline();

  while (--argc > 0) {
    char * arg = *++argv;
    unsigned char cmd = arg[0];
    printf("1:"); printSharedStateSelector(&sss); printf(" 2:"); printSharedStateSelector(&sss2); 
    printf(" Cmd:'%s' -- ",&arg[0]);

    switch (cmd) {
    case '2':
      sss2 = sss;
      printf("Copied 1->2\n");
      break;

    case 'x':
      {
        struct SharedStateSelector tmp = sss2;
        sss2 = sss;
        sss = tmp;
        printf("Exchanged 1<->2\n");
      }
      break;

    case 't':
      {
        printf("Transfer req from 1 to 2 (uinimplemented)\n");
        break;
      }

    case '0': 
    case '1':
      sss.pru = cmd - '0';
      printf("PRU%d\n",sss.pru);
      break;
      
    case 'a':
    case 'b':
    case 'c':
      sss.prudir = cmd - 'a';
      printf("PRUdir%d\n",sss.prudir);
      break;

    case 'f':
    case 's':
    case 'p':
      if (cmd=='f') sss.bulk = 0; else
      if (cmd=='s') sss.bulk = 1; else
      if (cmd=='p') sss.bulk = -1;
      printf("\n");
      break;

    case 'i':
    case 'o':
      sss.inbound = (cmd=='o') ? 0 : 1;
      printf("I%d\n",sss.inbound);
      break;

    case 'w': {
      unsigned arglen = strlen(&arg[0]);
      if (arglen < 2) printf("wPACKET\n");
      else {
        if (sss.bulk < 0) {
          printf("Cannot autoselect QoS for output; skipping\n");
        } else {
          struct PacketBuffer * pb = getPacketBufferIfAny(ss,&sss);
          if (!pb) FATAL;
          int ret = pbWritePacketIfPossible(pb, (unsigned char *) &arg[1], arglen-1);
          if (ret == 0) printf("Wrote %d\n",arglen-1);
          else FATAL;
        }
      }
    }
      break;

    case '!': {
      initSharedState(ss);
      printf("Initted!\n");
    }
      break;

    case 'r': {
      unsigned char buffer[257];
      struct PacketBuffer * pb = getPacketBufferIfAny(ss,&sss);
      if (!pb) 
        printf("Nothing pending for bulk or priority\n");
      else {
        int ret = pbReadPacketIfPossible(pb, buffer, 256);
        if (ret == 0) printf("Nothing to read\n");
        else if (ret > 0) { buffer[ret] = 0; printf("Read(%d) %d='%s'\n", sss.bulk, ret, buffer); }
        else {errno = -ret; FATAL; }
      }
    }
      break;

    default: FATAL;
      
    }
  }

  /*
  (*(unsigned long *) &ss->pruState[0]) = ('0'<<24)|('P'<<16)|tag;
  (*(unsigned long *) &ss->pruState[1]) = ('1'<<24)|('P'<<16)|tag;

  printf("PRU0 0x%08lx\n",(*(unsigned long *) &ss->pruState[0]));
  printf("PRU1 0x%08lx\n",(*(unsigned long *) &ss->pruState[1]));
  */
  if(munmap(sharedStateVirtualBaseAddress, MAP_SIZE) == -1) FATAL;
  close(fd);
  return 0;
}

