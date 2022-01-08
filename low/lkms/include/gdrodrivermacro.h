#ifndef GDRODRIVERMACRO_H
#define GDRODRIVERMACRO_H

//// THE GDRO DRIVER-VS-PIN DATA

/* GDRODRIVERMACRO() holds the GDRO driver-to-ITC+pin mapping.  Each
   driver is either an empath or a jerk, and uses two gpios on
   separate ITCS. IPIN is IRQLK or IGRLK, OPIN is ORQLK or OGRLK */

#define GDRODRIVERMACRO()          \
 /*  NAME JERK IITC OITC IOPIN  */ \
   XX(NE2,  0, NE, NE, GRLK)       \
   XX(ET2,  0, ET, ET, GRLK)       \
   XX(SE2,  0, SE, SE, GRLK)       \
   XX(SW2,  1, SW, SW, GRLK)       \
   XX(WT2,  1, WT, WT, GRLK)       \
   XX(NW2,  1, NW, NW, GRLK)       \
   XX(NE3,  0, NE, NW, RQLK)       \
   XX(SE3,  1, SE, ET, RQLK)       \
   XX(WT3,  0, WT, SW, RQLK)       \
   XX(SW3,  0, SW, SE, RQLK)       \
   XX(NW3,  1, NW, WT, RQLK)       \
   XX(ET3,  0, ET, NE, RQLK)       \
//END

#define XX(NM,JK,IITC,OITC,IOPIN) GDRO_##NM,
enum { GDRODRIVERMACRO() GDRO_MIN = GDRO_NE2, GDRO_MAX = GDRO_ET3, GDRO_COUNT };
#undef XX

#endif /*GDRODRIVERMACRO_H*/
