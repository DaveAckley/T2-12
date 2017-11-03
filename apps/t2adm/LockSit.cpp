#include <stdlib.h>   // for abort()
#include <string.h>   // for strlen
#include <stdio.h>    // for snprintf
#include "LockSit.h"

const BrickDir dirToBrickDir[DIR_COUNT] =
  { (BrickDir) BRICK_DIR_COUNT, // DIR_NORTH -- illegal
    BRICK_DIR_NORTHEAST,
    BRICK_DIR_EAST,
    BRICK_DIR_SOUTHEAST,
    (BrickDir) BRICK_DIR_COUNT, // DIR_SOUTH -- illegal
    BRICK_DIR_SOUTHWEST,
    BRICK_DIR_WEST,
    BRICK_DIR_NORTHWEST
  };

const Dir brickDirToDir[BRICK_DIR_COUNT] =
  {
    DIR_EAST,
    DIR_SOUTHEAST,
    DIR_SOUTHWEST,
    DIR_WEST,
    DIR_NORTHWEST,
    DIR_NORTHEAST
  };


const char * dirLabels[DIR_COUNT] =
  { "NT", "NE", "ET", "SE", "ST", "SW", "WT", "NW" };

const char * stateLabels[LOCK_STATE_COUNT] =
  { "IDLE  ", "TAKEN ", "GIVEN ", "RESET ", "FAILED", "FLUX  " };

void LockSit::ReadITCStatus()
{
  int ret;
  ret = read(itcfd,itcbuffer,ITC_READ_COUNT);
  dieNeg(ret,"read");
  dieNeg(ret-6,"amount");
}

void LockSit::CheckITCStatus()
{
  ReadITCStatus();
  for (int i = BRICK_DIR_MIN; i < BRICK_DIR_COUNT; ++i) {
    locks[i].SampleStatus(itcbuffer);
  }
}

void LockSit::DrawITCStatus()
{
  for (int i = BRICK_DIR_MIN; i < BRICK_DIR_COUNT; ++i) {
    locks[i].DrawStatus(hidenc);
  }
}

int ITCLock::StateFromStatus(char stat[ITC_READ_COUNT], unsigned dir)
{
  unsigned bit = 1<<dir;
  if (stat[0]&bit) return LOCK_TAKEN;
  if (stat[2]&bit) return LOCK_GIVEN;
  if (stat[3]&bit) return LOCK_IDLE;
  if (stat[4]&bit) return LOCK_FAILED;
  if (stat[5]&bit) return LOCK_RESET;
  return LOCK_UNSETTLED;
}

void ITCLock::SampleStatus(char itcstatus[ITC_READ_COUNT])
{
  state = StateFromStatus(itcstatus,direction);
  for (int i = LOCK_MIN; i <= LOCK_MAX; ++i) {
    int hit = 0;
    if (i == state) hit = 3<<SAMPLE_SHIFT_BITS;
    stateWeights[i] =
      ((stateWeights[i]<<SAMPLE_SHIFT_BITS)-stateWeights[i]+hit)>>SAMPLE_SHIFT_BITS;
  }
}

void ITCLock::DrawStatus(HideNC& hidenc)
{
  DrawStringRelative(hidenc, 0, 0, GetLabel());
  DrawStringRelative(hidenc, 1, 1, GetStateLabel());
  for (int i = LOCK_MIN; i < LOCK_STATE_COUNT; ++i) {
    char buffer[200];
    int mct = GetStateMct((LockState) i);
    snprintf(buffer,200,"%2d %s       ",mct/10,GetLabelForState((LockState) i));
    DrawStringRelative(hidenc, 4, i+3, buffer);
  }
}

void ITCLock::DrawStringRelative(HideNC& hidenc, int offx, int offy, const char * label)
{
  int width = hidenc.GetMaxX()-1;
  int height = hidenc.GetMaxY()-1;
  int xq, yq;
  int dx, dy;
  int bx, by;
  switch (direction) {
  case BRICK_DIR_NORTHEAST: xq = 3; yq = 0; dx = 1; dy = 0; bx = offx; by = offy; break;
  case BRICK_DIR_EAST:      xq = 4; yq = 2; dx = 0; dy = 1; bx = -offy; by = offx; break;
  case BRICK_DIR_SOUTHEAST: xq = 3; yq = 4; dx = 1; dy = 0; bx = offx; by = -offy; break;
  case BRICK_DIR_SOUTHWEST: xq = 1; yq = 4; dx = 1; dy = 0; bx = offx; by = -offy; break;
  case BRICK_DIR_WEST:      xq = 0; yq = 2; dx = 0; dy = 1; bx = offy; by = offx; break;
  case BRICK_DIR_NORTHWEST: xq = 1; yq = 0; dx = 1; dy = 0; bx = offx; by = offy; break;
  }

  if (!label) label = "<NULL>";
  int llen = strlen(label);
  int x = xq*width/4 - dx*llen/2;
  int y = yq*height/4 - dy*llen/2;
  for (int l = 0; l < llen; ++l) {
    hidenc.MvPrintW(y+by,x+bx,"%c",label[l]);
    x += dx;
    y += dy;
  }
}
