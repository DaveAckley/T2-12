#ifndef ITCIMPL_H
#define ITCIMPL_H

#include <linux/init.h>            /* Macros used to mark up functions e.g. __init __exit */
#include <linux/module.h>          /* Core header for loading LKMs into the kernel */
#include <linux/device.h>          /* Header to support the kernel Driver Model */
#include <linux/kernel.h>          /* Contains types, macros, functions for the kernel */
#include <linux/fs.h>              /* Header for the Linux file system support */
#include <asm/uaccess.h>           /* Required for the copy to user function */
#include <linux/mutex.h>	   /* Required for the mutex functionality */
#include <linux/kthread.h>         /* For thread functions */
#include <linux/random.h>          /* for prandom_u32_max() */

//// THE DIRECTION-VS-PIN DATA

/* DIRDATAMACRO() holds the ITC-to-GPIO mapping.  Each ITC is either a
   fred or a ginger, and uses four gpios, labeled IRQLK, IGRLK, ORQLK,
   and OGRLK.*/

#define DIRDATAMACRO()                  \
/*  DIR FRED IRQLK IGRLK ORQLK OGRLK */ \
  XX(ET,   1,  69,   68,   66,   67)	\
  XX(SE,   1,  26,   27,   45,   23)	\
  XX(SW,   0,  61,   10,   65,   22)	\
  XX(WT,   0,  81,    8,   11,    9)	\
  XX(NW,   0,  79,   60,   80,   78)	\
  XX(NE,   1,  49,   14,   50,   51) 

#define XX(DC,fr,p1,p2,p3,p4) DIR_##DC,
enum { DIRDATAMACRO() DIR_MIN = DIR_ET, DIR_MAX = DIR_NE, DIR_COUNT };
#undef XX


//// TYPES, CONSTANTS, DATA STRUCTURES
enum { PIN_MIN = 0, PIN_IRQLK = PIN_MIN, PIN_IGRLK, PIN_ORQLK, PIN_OGRLK, PIN_MAX = PIN_OGRLK, PIN_COUNT };

typedef unsigned long JiffyUnit;
typedef unsigned long ITCCounter;
typedef unsigned char ITCDir;
typedef ITCDir ITCDirSet[DIR_COUNT];
typedef int ITCIteratorUseCount;
typedef unsigned char ITCState;
typedef unsigned int BitValue;
typedef int IRQNumber;

typedef struct itciterator {
  ITCIteratorUseCount m_usesRemaining;
  ITCIteratorUseCount m_averageUsesPerShuffle;
  ITCDir m_nextIndex;
  ITCDirSet m_indices;
} ITCIterator;

void itcIteratorShuffle(ITCIterator * itr) ;

void itcIteratorInitialize(ITCIterator * itr, ITCIteratorUseCount avguses) ;

static inline void itcIteratorStart(ITCIterator * itr) {
  if (--itr->m_usesRemaining < 0) itcIteratorShuffle(itr);
  itr->m_nextIndex = 0;
}
static inline bool itcIteratorHasNext(ITCIterator * itr) {
  return itr->m_nextIndex < DIR_COUNT;
}
static inline ITCDir itcIteratorGetNext(ITCIterator * itr) {
  BUG_ON(!itcIteratorHasNext(itr));
  return itr->m_indices[itr->m_nextIndex++];
}

typedef struct itcInfo {
  const struct gpio * const pins;
  const ITCDir direction;
  const bool isFred;
  BitValue pinStates[PIN_COUNT];
  ITCState state;
  ITCCounter fails;
  ITCCounter resets;
  ITCCounter locksAttempted;
  ITCCounter locksAcquired;
  ITCCounter locksGranted;
  ITCCounter locksContested;
  ITCCounter interruptsTaken;
  ITCCounter edgesMissed;
  JiffyUnit lastActive;
  JiffyUnit lastReported;
} ITCInfo;

typedef struct moduleData {
  ITCIterator userContextIterator;
  JiffyUnit moduleLastActive;
  ITCInfo itcInfo[DIR_COUNT];
  JiffyUnit userRequestTime;
  u8 userLockset;
  bool userRequestActive;
} ModuleData;

int itcThreadRunner(void *arg) ;
void itcImplInit(void) ;
void itcImplExit(void) ;
int itcGetCurrentLockInfo(u8 * buffer, int len) ;

// itcInterpretCommandByte
// Returns:
//
//  o -ENODEV if currently unimplemented code is encountered
//
//  o -EINVAL if either of the top two bits of lockset are non-zero,
//     and in this case the current lock posture remains unchanged
//
//  o -EBUSY if any requested locks were already given to far side,
//    and in this case any locks that we are holding will be released
//
//  o 1 if we successfully took all requested locks and released any
//    others that we may have been holding

ssize_t itcInterpretCommandByte(u8 cmd) ;

extern ModuleData md;

#endif /* ITCIMPL_H */
