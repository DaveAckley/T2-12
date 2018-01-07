#include <linux/random.h>          /* for prandom_u32_max() */
#include <linux/bug.h>
#include "ITCIterator.h"

void itcIteratorInitialize(ITCIterator * itr, ITCIteratorUseCount avguses) {
  int i;
  BUG_ON(!itr);
  BUG_ON(avguses <= 0);
  BUG_ON((avguses<<1) <= 0);
  itr->m_averageUsesPerShuffle = avguses;
  for (i = 0; i < ITC_DIR_COUNT; ++i)
    itr->m_indices[i] = i; /*0,1,2,3,4,5*/
  itcIteratorShuffle(itr);
}

void itcIteratorShuffle(ITCIterator * itr) {
  ITCDir i;
  BUG_ON(!itr);
  itr->m_usesRemaining = 
    prandom_u32_max(itr->m_averageUsesPerShuffle<<1) + 1; /* max is double avg, given uniform random */

  for (i = ITC_DIR_COUNT - 1; i > 0; --i) {
    int j = prandom_u32_max(i+1); /* generates 0..DIR_MAX down to 0..1 */
    if (i != j) {
      ITCDir tmp = itr->m_indices[i];
      itr->m_indices[i] = itr->m_indices[j];
      itr->m_indices[j] = tmp;
    }
  }

  printk(KERN_DEBUG "ITC %p iterator order is %d%d%d%d%d%d for next %d uses\n",
         itr,
         itr->m_indices[0],
         itr->m_indices[1],
         itr->m_indices[2],
         itr->m_indices[3],
         itr->m_indices[4],
         itr->m_indices[5],
         itr->m_usesRemaining
         );
}

