#ifndef ITC_ITERATOR_H
#define ITC_ITERATOR_H

#include <linux/random.h>          /* for prandom_u32_max() */
#include <linux/bug.h>             /* for BUG_ON */
#include "dirdatamacro.h"          /* Get itc pin info and basic enums */ 

typedef unsigned char ITCDir;
typedef ITCDir ITCDirSet[DIR6_COUNT];
typedef int ITCIteratorUseCount;

typedef struct itciterator {
  ITCIteratorUseCount m_usesRemaining;
  ITCIteratorUseCount m_averageUsesPerShuffle;
  ITCDir m_nextIndex;
  ITCDirSet m_indices;
} ITCIterator;

static inline void itcIteratorShuffle(ITCIterator * itr) {
  ITCDir i;
  BUG_ON(!itr);
  itr->m_usesRemaining = 
    prandom_u32_max(itr->m_averageUsesPerShuffle<<1) + 1; /* max is double avg, given uniform random */

  for (i = DIR6_MAX; i > 0; --i) {
    int j = prandom_u32_max(i+1); /* generates 0..DIR6_MAX down to 0..1 */
    if (i != j) {
      ITCDir tmp = itr->m_indices[i];
      itr->m_indices[i] = itr->m_indices[j];
      itr->m_indices[j] = tmp;
    }
  }
}

static inline void itcIteratorInitialize(ITCIterator * itr, ITCIteratorUseCount avguses)
{
  int i;
  BUG_ON(!itr);
  BUG_ON(avguses <= 0);
  BUG_ON((avguses<<1) <= 0);
  itr->m_averageUsesPerShuffle = avguses;
  for (i = 0; i < DIR6_COUNT; ++i) itr->m_indices[i] = i;
  itcIteratorShuffle(itr);
}

static inline void itcIteratorStart(ITCIterator * itr) {
  if (--itr->m_usesRemaining < 0) itcIteratorShuffle(itr);
  itr->m_nextIndex = 0;
}
static inline bool itcIteratorHasNext(ITCIterator * itr) {
  return itr->m_nextIndex < DIR6_COUNT;
}
static inline ITCDir itcIteratorGetNext(ITCIterator * itr) {
  BUG_ON(!itcIteratorHasNext(itr));
  return itr->m_indices[itr->m_nextIndex++];
}

#endif /* ITC_ITERATOR_H */
