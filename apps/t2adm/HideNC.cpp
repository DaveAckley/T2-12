#include "HideNC.h"

#include <ncurses.h> /* horrible polluter ncurses only included here */
#include <unistd.h>  /* for sleep */
#include <stdlib.h>  /* for unsetenv */

#define DELAY 30000

HideNC::HideNC() 
  : initted(false)
  , max_x(0)
  , max_y(0)
  , running(0)
  , redraw(1)
{
}

bool HideNC::Startup() {
  if (initted) return false;
  // Unset LINES and COLUMNS so ncurses will respond to sigwinch
  unsetenv("LINES");
  unsetenv("COLUMNS");

  initscr();
  noecho();
  cbreak();
  raw();
  keypad(stdscr, TRUE);
  nodelay(stdscr, TRUE);
  curs_set(FALSE);
  getmaxyx(stdscr, max_y, max_x);

  initted = true;
  running = true;
  return true;
}

bool HideNC::Shutdown() {
  if (!initted) return false;
  endwin();
  initted = false;
  return true;
}

bool HideNC::IsRunning() {
  return running!=0;
}

int HideNC::Getch() {
  int ch = getch();
  if (ch == KEY_RESIZE) {
    redraw = 1;
    getmaxyx(stdscr, max_y, max_x);
  } else if (ch == 'q' || ch == '\021' || ch == '\003') // q, ^Q, ^C
    running = 0;
  else 
    return ch;
  return -1;
}

void HideNC::Erase() { erase(); }

void HideNC::MvPrintW(int y, int x, const char * str) { mvprintw(y,x,str); }

bool HideNC::NeedRedraw() { return redraw; }

void HideNC::FinishedRedraw() { redraw = 0; }

void HideNC::Refresh() { refresh(); }

void HideNC::NapMS(int ms) { napms(ms); }
