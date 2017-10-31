#include <stdlib.h>   // for abort()
#include <string.h>   // for strlen
#include "LockSit.h"

const char * dirLabels[DIR_COUNT] =
  { "NT", "NE", "ET", "SE", "ST", "SW", "WT", "NW" };

const char * stateLabels[LOCK_STATE_COUNT] =
  { "IDLE  ", "TAKEN ", "GIVEN ", "RESET ", "FAILED" };

void LockSit::CheckITCStatus(bool alldirs)
{
  for (int i = DIR_MIN; i < DIR_COUNT; ++i) {
    if (!alldirs && (i == DIR_NORTH || i == DIR_SOUTH)) continue;
    locks[i].CheckStatus();
  }
}

void LockSit::DrawITCStatus(bool alldirs)
{
  for (int i = DIR_MIN; i < DIR_COUNT; ++i) {
    if (!alldirs && (i == DIR_NORTH || i == DIR_SOUTH)) continue;
    locks[i].DrawStatus(hidenc);
  }
}

void ITCLock::CheckStatus()
{
  int diff = LOCK_STATE_COUNT - state;
  if ((random()%(diff*diff*8)) == 0)
    state = random()%LOCK_STATE_COUNT;
}

void ITCLock::DrawStatus(HideNC& hidenc)
{
  DrawStringRelative(hidenc, 0, 0, GetLabel());
  DrawStringRelative(hidenc, 1, 1, GetStateLabel());

}

void ITCLock::DrawStringRelative(HideNC& hidenc, int offx, int offy, const char * label)
{
  int width = hidenc.GetMaxX()-1;
  int height = hidenc.GetMaxY()-1;
  int xq, yq;
  int dx, dy;
  int bx, by;
  switch (direction) {
  case DIR_NORTH:     xq = 2; yq = 0; dx = 1; dy = 0; bx = offx; by = offy; break;
  case DIR_NORTHEAST: xq = 3; yq = 0; dx = 1; dy = 0; bx = offx; by = offy; break;
  case DIR_EAST:      xq = 4; yq = 2; dx = 0; dy = 1; bx = -offy; by = offx; break;
  case DIR_SOUTHEAST: xq = 3; yq = 4; dx = 1; dy = 0; bx = offx; by = -offy; break;
  case DIR_SOUTH:     xq = 2; yq = 4; dx = 1; dy = 0; bx = offx; by = -offy; break;
  case DIR_SOUTHWEST: xq = 1; yq = 4; dx = 1; dy = 0; bx = offx; by = -offy; break;
  case DIR_WEST:      xq = 0; yq = 2; dx = 0; dy = 1; bx = offy; by = offx; break;
  case DIR_NORTHWEST: xq = 1; yq = 0; dx = 1; dy = 0; bx = offx; by = offy; break;
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
