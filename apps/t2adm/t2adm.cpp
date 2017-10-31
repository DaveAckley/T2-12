#include "t2adm.h"
#include <string.h>

int main() {
  int x = 0, y = 1, next_x = 0, direction = 1;
  HideNC hnc;
  LockSit ls(hnc);

  hnc.Startup();

  while (hnc.IsRunning()) {
    int max_x = hnc.GetMaxX();
    int ch = hnc.Getch();
    if (ch == 'd') direction *= -1;

    if (hnc.NeedRedraw()) {
      const char * title = "t2adm v0.0.0.1";
      hnc.Erase();
      hnc.MvPrintW(0,(max_x-strlen(title))/2,title);
      hnc.FinishedRedraw();
    }

    hnc.MvPrintW(y, x, " ");
    next_x = x + direction;
    if (next_x > max_x) {
      next_x = max_x;
      direction = -1;
    } else if (next_x < 0) {
      next_x = 0;
      direction = 1;
    }
    x += direction;
    hnc.MvPrintW(y, x, "o");
    ls.DrawITCStatus();
    hnc.Refresh();
    hnc.NapMS(1000/30); // 30 FPS
  }
  hnc.Shutdown();
  return 1;
}
