#ifndef LOCKSIT_H   /* -*- C++ -*- */
#define LOCKSIT_H

#include "HideNC.h"
#include <stdio.h> /* for perror */
#include <stdlib.h> /* for exit */
#include <fcntl.h> /* for O_RDONLY */
#include<unistd.h> /* for read() */


enum LockState { LOCK_MIN=0, LOCK_IDLE=LOCK_MIN, LOCK_TAKEN, LOCK_GIVEN, LOCK_RESET, LOCK_UNSETTLED, LOCK_FAILED, LOCK_MAX=LOCK_FAILED };

enum { LOCK_STATE_COUNT = LOCK_MAX+1 };

enum { ITC_READ_COUNT = 6 };


#define DEVICE_NAME "/dev/itc/locks"

static inline void dieNeg(int val, const char * msg)
{
  if (val < 0) {
    perror(msg);
    exit(-val);
  }
}

extern const char * stateLabels[LOCK_STATE_COUNT];

enum Dir { 
  DIR_MIN, 
  DIR_NORTH=DIR_MIN, DIR_NORTHEAST, DIR_EAST, DIR_SOUTHEAST, 
  DIR_SOUTH, DIR_SOUTHWEST, DIR_WEST, DIR_NORTHWEST,
  DIR_MAX=DIR_NORTHWEST
};

enum { DIR_COUNT = DIR_MAX+1 };

enum BrickDir {
  BRICK_DIR_MIN, 
  BRICK_DIR_EAST=DIR_MIN,
  BRICK_DIR_SOUTHEAST, 
  BRICK_DIR_SOUTHWEST, 
  BRICK_DIR_WEST, 
  BRICK_DIR_NORTHWEST, 
  BRICK_DIR_NORTHEAST, 
  BRICK_DIR_MAX=BRICK_DIR_NORTHEAST
};

enum { BRICK_DIR_COUNT = BRICK_DIR_MAX+1 };

extern const Dir brickDirToDir[BRICK_DIR_COUNT];

extern const BrickDir dirToBrickDir[DIR_COUNT];

extern const char * dirLabels[DIR_COUNT];

struct ITCLock {
  static const int SAMPLE_SHIFT_BITS = 12; // 4095/4096 ~ 99.975% old + 0.025% new

  BrickDir direction;
  int state;
  unsigned stateWeights[LOCK_STATE_COUNT];
  unsigned GetStateMct(LockState state) {
    return (1000*stateWeights[state])>>SAMPLE_SHIFT_BITS;
  }
  static int StateFromStatus(char itstatus[ITC_READ_COUNT], unsigned dir) ;
  ITCLock() 
    : direction(BRICK_DIR_MIN)
    , state(-1) 
  { }
  void Init(BrickDir dir) {
    direction = dir;
    state = LOCK_FAILED;
    for (int i = 0; i < LOCK_STATE_COUNT; ++i) {
      stateWeights[i] = (1<<SAMPLE_SHIFT_BITS)/LOCK_STATE_COUNT;
    }
  }
  static const char * GetLabelForBrickDir(BrickDir bdir) {
    return dirLabels[brickDirToDir[bdir]];
  }
  const char * GetLabel() const { return GetLabelForBrickDir(direction); }

  static const char * GetLabelForState(LockState state) { return stateLabels[state]; }
  const char * GetStateLabel() const { return GetLabelForState((LockState) state); }
  void SampleStatus(char stat[ITC_READ_COUNT]) ;
  void DrawStatus(HideNC& hnc) ;
  void DrawStringRelative(HideNC& hnc, int offx, int offy, const char * string) ;
};

class LockSit {
  static const int LOCK_COUNT = BRICK_DIR_COUNT;
  HideNC & hidenc;
  ITCLock locks[LOCK_COUNT];
  int itcfd;
  char itcbuffer[ITC_READ_COUNT];
public:
  void ReadITCStatus() ;
  LockSit(HideNC& h) 
    : hidenc(h) 
  {
    for (int i = BRICK_DIR_MIN; i < BRICK_DIR_COUNT; ++i)
      locks[i].Init((BrickDir) i);
    itcfd = open(DEVICE_NAME, O_RDWR);
    dieNeg(itcfd,DEVICE_NAME " open");
  }
  void CheckITCStatus() ;
  void DrawITCStatus() ;
};

#endif /* LOCKSIT_H */
