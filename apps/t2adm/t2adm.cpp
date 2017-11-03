#include "t2adm.h"
#include <string.h>

void nextDir(int & dx, int & dy) {
  if (dx > 0 && dy == 0) { dx = 0; dy = 1; return; }
  if (dx == 0 && dy > 0) { dx = -1; dy = 0; return; }
  if (dx < 0 && dy == 0) { dx = 0; dy = -1; return; }
/*if (dx == 0 && dy < 0)*/ { dx = 1; dy = 0; return; }
}

int main() {
  int x = 0, y = 0, dx = 1, dy = 0;
  HideNC hnc;
  LockSit ls(hnc);

  hnc.Startup();

  while (hnc.IsRunning()) {
    int max_x = hnc.GetMaxX();
    int max_y = hnc.GetMaxY();
    int ch = hnc.Getch();
    if (ch == 'd') nextDir(dx,dy);

    if (hnc.NeedRedraw()) {
      const char * title = "t2adm v0.0.0.2";
      hnc.Erase();
      hnc.MvPrintW(max_y/2,(max_x-strlen(title))/2,title);
      hnc.FinishedRedraw();
    }

    hnc.MvPrintW(y, x, " ");
    while (!hnc.InBounds(x+dx, y+dy)) nextDir(dx,dy);
    ls.CheckITCStatus();
    ls.DrawITCStatus();
    hnc.MvPrintW(0,0,"");
    hnc.Refresh();
    hnc.NapMS(1000/30); // 30 FPS
  }
  hnc.Shutdown();
  return 1;
}
