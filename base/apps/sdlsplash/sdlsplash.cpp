#include <stdio.h>
#include <signal.h>
#include "SDL.h"
#include "SDL_image.h"

#define WIDTH 480
#define HEIGHT 320


static void exitImmediately(int sig)
{
  abort();
}

int main(int argc, char **argv)
{
  int sec = 5;
  const char * path;
  {
    const char * prg = argv[0];
    --argc; ++argv;
    if (argc <= 0) {
      fprintf(stderr,"Usage: %s FILE [SEC=5]\n",prg);      
      return 99;
    }
    path = argv[0];

    const char * numa = "5";
    --argc; ++argv;

    if (argc > 0) {
      numa = argv[0];
      --argc; ++argv;
    }

    char * endptr;
    sec = strtol(numa, &endptr, 10);
    if (*numa == 0 || *endptr != 0 || sec < 0) {
      fprintf(stderr,"Usage: %s FILE SEC (%d/%s)\n", prg, sec,numa);      
      return 97;
    }
  }

  {
    unsigned int flags = SDL_INIT_TIMER|SDL_INIT_VIDEO|SDL_INIT_NOPARACHUTE;
    int ret = SDL_Init(flags);
    if (ret) {
      fprintf(stderr,"SDL_Init(0x%x) failed: %s\n",
              flags,
              SDL_GetError());
      return 1;
    }
  }

  SDL_Surface* screen = 0;

  unsigned int swidth = WIDTH;
  unsigned int sheight = HEIGHT;
  {
    unsigned int flags = SDL_SWSURFACE;  

    screen = SDL_SetVideoMode(swidth, sheight, 32, flags);

    if (screen == 0) {
      fprintf(stderr,"SDL_SetVideoMode(%d,%d,32,0x%x) failed: %s\n",
              swidth, sheight, flags,
              SDL_GetError());
      return 2;
    }
  }

  {
    unsigned int gotWidth = SDL_GetVideoSurface()->w;
    unsigned int gotHeight = SDL_GetVideoSurface()->h;
    if (gotWidth != swidth || gotHeight != sheight) {
      fprintf(stderr,"Screen %dx%d (wanted %dx%d)\n",
              gotWidth, gotHeight,
              swidth, sheight);
      return 3;
    }
  }

  SDL_Surface* imgsurf = 0;
  {
    imgsurf = IMG_Load(path);
    if (!imgsurf) {
      fprintf(stderr,"IMG_Load(%s) failed: %s\n",
              path,
              SDL_GetError());
      return 4;
    }

  }

  /* Try to fricken die a little fricken faster sheesh */
  signal(SIGTERM, exitImmediately);
  
  {
    SDL_Rect rcdest = { 0, 0, 0, 0 };
    SDL_BlitSurface(imgsurf, 0, screen, &rcdest);
    SDL_UpdateRect(screen, 0, 0, swidth, sheight);
    unsigned ms = 0;
    const unsigned goalms = 1000u*(unsigned) sec;
    while ( ++ms < goalms ) // default five second splash
      SDL_Delay(1);
  }


  {
    SDL_FreeSurface(imgsurf);
    SDL_Quit();
  }

  return 0;
}
