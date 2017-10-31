#ifndef LOCKSIT_H   /* -*- C++ -*- */
#define LOCKSIT_H

#include "HideNC.h"

enum LockState { LOCK_IDLE, LOCK_TAKEN, LOCK_GIVEN, LOCK_RESET, LOCK_FAILED, LOCK_OTHER };
enum Dir { 
  DIR_MIN, 
  DIR_NORTH=DIR_MIN, DIR_NORTHEAST, DIR_EAST, DIR_SOUTHEAST, 
  DIR_SOUTH, DIR_SOUTHWEST, DIR_WEST, DIR_NORTHWEST, 
  DIR_COUNT 
};

struct ITCLock {
  Dir direction;
  int state;
  ITCLock() 
    : direction(DIR_COUNT)
    , state(-1) 
  { }
  void Init(Dir dir) {
    direction = dir;
    state = LOCK_FAILED;
  }
  void DrawStatus(HideNC& hnc) ;
};

class LockSit {
  static const int LOCK_COUNT = 6;
  HideNC & hidenc;
  ITCLock locks[LOCK_COUNT];
public:
  LockSit(HideNC& h) 
    : hidenc(h) 
  {
    for (int i = DIR_MIN; i < DIR_COUNT; ++i)
      locks[i].Init((Dir) i);
  }
  void CheckITCStatus() ;
  void DrawITCStatus() ;
};

#endif /* LOCKSIT_H */
