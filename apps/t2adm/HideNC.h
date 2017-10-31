#ifndef HIDENC_H   /* -*- C++ -*- */
#define HIDENC_H

class HideNC {
  bool initted;
  int max_x, max_y;
  int running;
  int redraw;

public:
  HideNC() ;

  // I generally dislike capitalized method names but in here it's a
  // safe way to get OoB wrt all the ncurses namespace pollution.
  bool Startup() ;

  bool Shutdown() ;

  bool IsRunning() ;

  int Getch() ;
  void Erase() ;
  void Refresh() ;
  void NapMS(int ms) ;

  void MvPrintW(int y, int x, const char * fmt, ...) ;

  bool NeedRedraw() ;

  void FinishedRedraw() ;

  int GetMaxX() const { return max_x; }

  int GetMaxY() const { return max_y; }

  bool InBounds(int x, int y) const {
    if (x < 0 || x >= GetMaxX()) return false;
    if (y < 0 || y >= GetMaxY()) return false;
    return true;
  }
};

#endif /* HIDENC_H */

