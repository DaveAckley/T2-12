#ifndef LOCKSIT_H   /* -*- C++ -*- */
#define LOCKSIT_H

#include "HideNC.h"

enum LockState { LOCK_IDLE, LOCK_TAKEN, LOCK_GIVEN, LOCK_RESET, LOCK_FAILED, LOCK_MAX=LOCK_FAILED };

enum { LOCK_STATE_COUNT = LOCK_MAX+1 };


extern const char * stateLabels[LOCK_MAX+1];

enum Dir { 
  DIR_MIN, 
  DIR_NORTH=DIR_MIN, DIR_NORTHEAST, DIR_EAST, DIR_SOUTHEAST, 
  DIR_SOUTH, DIR_SOUTHWEST, DIR_WEST, DIR_NORTHWEST,
  DIR_MAX=DIR_NORTHWEST
};

enum { DIR_COUNT = DIR_MAX+1 };

extern const char * dirLabels[DIR_COUNT];

struct ITCLock {
  Dir direction;
  int state;
  ITCLock() 
    : direction(DIR_MIN)
    , state(-1) 
  { }
  void Init(Dir dir) {
    direction = dir;
    state = LOCK_FAILED;
  }
  const char * GetLabel() const { return dirLabels[direction]; }
  const char * GetStateLabel() const { return stateLabels[state]; }
  void CheckStatus() ;
  void DrawStatus(HideNC& hnc) ;
  void DrawStringRelative(HideNC& hnc, int offx, int offy, const char * string) ;
};

class LockSit {
  static const int LOCK_COUNT = DIR_COUNT;
  HideNC & hidenc;
  ITCLock locks[LOCK_COUNT];
public:
  LockSit(HideNC& h) 
    : hidenc(h) 
  {
    for (int i = DIR_MIN; i < DIR_COUNT; ++i)
      locks[i].Init((Dir) i);
  }
  void CheckITCStatus(bool alldirs) ;
  void DrawITCStatus(bool alldirs) ;
};

#endif /* LOCKSIT_H */
