#ifndef ITCITERATOR_H
#define ITCITERATOR_H

enum { ITC_DIR__ET = 0,
       ITC_DIR__SE = 1,
       ITC_DIR__SW = 2,
       ITC_DIR__WT = 3,
       ITC_DIR__NW = 4,
       ITC_DIR__NE = 5,
       ITC_DIR_COUNT = 6 };
typedef unsigned char ITCDir;
typedef ITCDir ITCDirSet[ITC_DIR_COUNT];
typedef int ITCIteratorUseCount;

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
static inline unsigned itcIteratorHasNext(ITCIterator * itr) {
  return itr->m_nextIndex < ITC_DIR_COUNT;
}
static inline ITCDir itcIteratorGetNext(ITCIterator * itr) {
  BUG_ON(!itcIteratorHasNext(itr));
  return itr->m_indices[itr->m_nextIndex++];
}

#endif /* ITCITERATOR_H */
