#include <stdlib.h>   // for abort()
#include <string.h>   // for strlen
#include "LockSit.h"

void LockSit::CheckITCStatus()
{
  
}

void LockSit::DrawITCStatus()
{
  for (int i = DIR_MIN; i < DIR_COUNT; ++i)
    locks[i].DrawStatus(hidenc);
}

void ITCLock::DrawStatus(HideNC& hidenc)
{
  int width = hidenc.GetMaxX()-1;
  int height = hidenc.GetMaxY()-1;
  int xq, yq;
  int dx, dy;
  const char * label;
  switch (direction) {
  case DIR_NORTH:     xq = 2; yq = 0; dx = 1; dy = 0; label = "NT"; break;
  case DIR_NORTHEAST: xq = 3; yq = 0; dx = 1; dy = 0; label = "NE"; break;
  case DIR_EAST:      xq = 4; yq = 2; dx = 0; dy = 1; label = "ET"; break;
  case DIR_SOUTHEAST: xq = 3; yq = 4; dx = 1; dy = 0; label = "SE"; break;
  case DIR_SOUTH:     xq = 2; yq = 4; dx = 1; dy = 0; label = "ST"; break;
  case DIR_SOUTHWEST: xq = 1; yq = 4; dx = 1; dy = 0; label = "SW"; break;
  case DIR_WEST:      xq = 0; yq = 2; dx = 0; dy = 1; label = "WT"; break;
  case DIR_NORTHWEST: xq = 1; yq = 0; dx = 1; dy = 0; label = "NW"; break;
  default:
    abort();
  }
  int llen = strlen(label);
  int x = xq*width/4 - dx*llen/2;
  int y = yq*height/4 - dy*llen/2;
  for (int l = 0; l < llen; ++l) {
    hidenc.MvPrintW(y,x,"%c",label[l]);
    x += dx;
    y += dy;
  }
}
