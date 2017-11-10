#include "t2adm.h"
#include <string.h>
#define VERSION "v0.0.3"

void nextDir(int & dx, int & dy) {
  if (dx > 0 && dy == 0) { dx = 0; dy = 1; return; }
  if (dx == 0 && dy > 0) { dx = -1; dy = 0; return; }
  if (dx < 0 && dy == 0) { dx = 0; dy = -1; return; }
/*if (dx == 0 && dy < 0)*/ { dx = 1; dy = 0; return; }
}

#include <sys/sysinfo.h>
struct sysinfo info;
bool checkSysInfo() {
  long lastuptime = info.uptime;
  int ret;
  ret = sysinfo(&info);
  if (ret) {
    perror("sysinfo");
    abort();
  }
  return lastuptime != info.uptime;
}

const char * formatSysInfo() {
  const int BUF_SIZE = 1000;
  static char buffer[BUF_SIZE];

  int days, hours, minutes, seconds, i = 0;

  i += snprintf(&buffer[i],BUF_SIZE - i, "%s", "t2adm " VERSION " ");

  seconds = info.uptime % 60;
  minutes = (info.uptime / 60) % 60;
  hours = (info.uptime / (60*60)) % 24;
  days = info.uptime / (60*60*24);

  if (days) i += snprintf(&buffer[i],BUF_SIZE - i, "%dd ",days);
  if (hours) i += snprintf(&buffer[i],BUF_SIZE - i, "%2d:",hours);
  i += snprintf(&buffer[i],BUF_SIZE - i,"%02d:%02d",minutes,seconds);

  const float LOAD_DIV = 1<<16;
  i += snprintf(&buffer[i],BUF_SIZE - i," %4.2f %4.2f %4.2f",
                info.loads[0]/LOAD_DIV,
                info.loads[1]/LOAD_DIV,
                info.loads[2]/LOAD_DIV);

  while (i < 40)
    i += snprintf(&buffer[i],BUF_SIZE - i," ");

  return buffer;
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
      hnc.Erase();
      hnc.FinishedRedraw();
    }

    if (checkSysInfo()) {
      const char * title = formatSysInfo();
      hnc.MvPrintW(max_y/2,(max_x-strlen(title))/2,title);
    }

    hnc.MvPrintW(y, x, " ");
    while (!hnc.InBounds(x+dx, y+dy)) nextDir(dx,dy);
    ls.CheckITCStatus();
    ls.DrawITCStatus();
    hnc.MvPrintW(0,0,"");
    hnc.Refresh();
    hnc.NapMS(1000/100); // 10 FPS
  }
  hnc.Shutdown();
  return 1;
}
