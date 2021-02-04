#ifndef DIRDATAMACRO_H
#define DIRDATAMACRO_H

//// THE DIRECTION-VS-PIN DATA

/* DIRDATAMACRO() holds the ITC-to-GPIO mapping.  Each ITC is either a
   fred or a ginger, and uses four gpios, labeled IRQLK, IGRLK, ORQLK,
   and OGRLK.*/

#define DIRDATAMACRO()                           \
/*           DIR FRED IRQLK IGRLK ORQLK OGRLK */ \
/*0 0x01*/ XX(ET,   1,  69,   68,   66,   67)    \
/*1 0x02*/ XX(SE,   1,  26,   27,   45,   23)    \
/*2 0x04*/ XX(SW,   0,  61,   10,   65,   22)    \
/*3 0x08*/ XX(WT,   0,  81,    8,   11,    9)    \
/*4 0x10*/ XX(NW,   0,  79,   60,   80,   78)    \
/*5 0x20*/ XX(NE,   1,  49,   14,   50,   51) 

#define XX(DC,fr,p1,p2,p3,p4) DIR6_##DC,
enum { DIRDATAMACRO() DIR6_MIN = DIR6_ET, DIR6_MAX = DIR6_NE, DIR6_COUNT };
#undef XX

//// TYPES, CONSTANTS, DATA STRUCTURES
enum { PIN_MIN = 0, PIN_IRQLK = PIN_MIN, PIN_IGRLK, PIN_ORQLK, PIN_OGRLK, PIN_MAX = PIN_OGRLK, PIN_COUNT };

/* Define the state constants here so STATE_COUNT available to all */

/* GENERATE STATE CONSTANTS */
#include "RULES.h"
#define RSE(forState,output,settlement,...) RS(forState,forState,output,settlement,__VA_ARGS__)
#define RSN(forState,output,settlement,...) RS(forState,_,output,settlement,__VA_ARGS__)
#define RS(forState,ef,output,...) forState,
enum {
  ALLRULESMACRO()
  STATE_COUNT
};
#undef RS
#undef RSE
#undef RSN

#endif /*DIRDATAMACRO_H*/
