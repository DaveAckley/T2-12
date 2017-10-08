#include "itcimpl.h"
#include <linux/delay.h>	    /* for msleep() */
#include <linux/jiffies.h>	    /* for time_before(), time_after() */
#include <linux/interrupt.h>	    /* for interrupt functions.. */
#include <linux/gpio.h>		    /* for gpio functions.. */

static bool ledOn = 0;                      ///< Is the LED on or off? Used for flashing

enum { sRESET = 0,    		/** Initial and ground state, entered on any error */
       sIDLE,			/** Successfully initialized, lock is open */
       sTAKE,			/** We are attempting to take the lock  */
       sTAKEN,			/** We are confirmed as holding the lock  */
       sGIVE,			/** They are attempting to take the lock  */
       sGIVEN,			/** They are confirmed as holding the lock  */
       sSYNC11,			/** First state out of sRESET on way to sIDLE */
       sSYNC01,			/** Second state out of sRESET on way to sIDLE */
       sSYNC00,			/** Third and final state out of sRESET on way to sIDLE */
       sFAILED,			/** Something went wrong while we held the lock  */
};

enum { DIR_MIN = 0, DIR_ET = DIR_MIN, DIR_SE, DIR_SW, DIR_WT, DIR_NW, DIR_NE, DIR_MAX = DIR_NE, DIR_COUNT };
enum { PIN_MIN = 0, PIN_IRQLK = PIN_MIN, PIN_IGRLK, PIN_ORQLK, PIN_OGRLK, PIN_MAX = PIN_OGRLK, PIN_COUNT };

typedef unsigned long JiffyUnit;
typedef unsigned long ITCCounter;
typedef unsigned char ITCDir;
typedef unsigned char ITCState;
typedef int IRQNumber;
typedef struct itcInfo {
  const struct gpio * const pins;
  const ITCDir direction;
  IRQNumber qIRQLK;
  IRQNumber qIGRLK;
  ITCState state;
  ITCCounter resets;
  ITCCounter locksAttempted;
  ITCCounter locksAcquired;
  ITCCounter locksGranted;
  ITCCounter locksContested;
  JiffyUnit lastActive;
} ITCInfo;

static const char * dirnames[DIR_COUNT] = { "ET", "SE", "SW", "WT", "NW", "NE" };
const char * itcDirName(ITCDir d)
{
  if (d > DIR_MAX) return "(Illegal)";
  return dirnames[d];
}
  
#define XX(DC,p1,p2,p3,p4) {  	       \
    { p1, GPIOF_DIR_IN, #DC "_IRQLK"}, \
    { p2, GPIOF_DIR_IN, #DC "_IGRLK"}, \
    { p3, GPIOF_DIR_OUT,#DC "_ORQLK"}, \
    { p4, GPIOF_DIR_OUT,#DC "_OGRLK"}, }

static struct gpio pins[DIR_COUNT][4] = {
  XX(ET, 39, 38, 36, 37),
  XX(SE, 10, 11, 13,  9),
  XX(SW, 31, 54, 35,  8),
  XX(WT, 51, 52, 55, 53),
  XX(NW, 49, 30, 50, 48),
  XX(NE, 17, 96, 18, 19),
};
#undef XX

#define XX(DC) { .direction = DC, .pins = pins[DC] }
static ITCInfo itcInfo[DIR_COUNT] = {
  XX(DIR_ET), XX(DIR_SE), XX(DIR_SW), XX(DIR_WT), XX(DIR_NW), XX(DIR_NE),
};
#undef XX

void itcInitStructure(ITCInfo * itc)
{
  const char * dn = itcDirName(itc->direction);
  itc->state = sRESET;
  itc->resets = 1;
  itc->locksAttempted = 0;
  itc->locksAcquired = 0;
  itc->locksGranted = 0;
  itc->locksContested = 0;
  itc->lastActive = jiffies;

  printk(KERN_INFO "ITC init %s: IRQ=%d, IGR=%d, ORQ=%d, OGGR=%d\n",
	 dn,
	 itc->pins[PIN_IRQLK].gpio,itc->pins[PIN_IGRLK].gpio,
	 itc->pins[PIN_ORQLK].gpio,itc->pins[PIN_OGRLK].gpio);
  //XXX set up interrupts
  
}

void itcInitStructures(void) {
  int err;
  unsigned count = ARRAY_SIZE(pins)*ARRAY_SIZE(pins[0]);
  ITCDir i;

  printk(KERN_INFO "ITC allocating %d pins\n", count);

#if 0
  err = gpio_request_array(&pins[0][0], count);
  if (err) {
    printk(KERN_ALERT "ITC failed to allocate %d pin(s): %d\n", count, err);
  } else {
    printk(KERN_INFO "ITC allocated %d pins\n", count); 
  }
#else
  { /* Initialize gpios individually to get individual failures */
    unsigned n;
    for(n = 0; n < count; ++n) {
      struct gpio *g = &pins[0][0]+n;
      err = gpio_request_array(g, 1);
      if (err) {
        printk(KERN_INFO "ITC failed to allocate pin %d: %d\n", g->gpio, err);
      } else {
        printk(KERN_INFO "ITC allocated pin %d\n", g->gpio); 
      }
    }
  }
#endif

  for (i = DIR_MIN; i <= DIR_MAX; ++i) {
    BUG_ON(i != itcInfo[i].direction);  /* Assert we inited directions properly */
    itcInitStructure(&itcInfo[i]);
  }
}

void itcExitStructures(void) {
  unsigned count = ARRAY_SIZE(pins)*ARRAY_SIZE(pins[0]);

  gpio_free_array(&pins[0][0], count);
  printk(KERN_INFO "ITC freed %d pins\n", count); 
}

/** @brief The ITC main timing loop
 *
 *  @param arg A void pointer available to pass data to the thread
 *  @return returns 0 if successful
 */
int itcThreadRunner(void *arg){
  const int blinkPeriod = 10000;
   printk(KERN_INFO "itcThreadRunner: Started\n");
   while(!kthread_should_stop()){           // Returns true when kthread_stop() is called
      set_current_state(TASK_RUNNING);
      /*if (mode==FLASH)*/ ledOn = !ledOn;      // Invert the LED state
      //      else if (mode==ON) ledOn = true;
      //      else ledOn = false;
      printk(KERN_INFO "itc thread %zu %lu\n",ledOn, jiffies);
      //      gpio_set_value(gpioLED, ledOn);       // Use the LED state to light/turn off the LED
      set_current_state(TASK_INTERRUPTIBLE);
      msleep(blinkPeriod/2);                // millisecond sleep for half of the period
   }
   printk(KERN_INFO "itcThreadRunner: Stopping by request\n");
   return 0;
}

void itcImplInit(void)
{
  itcInitStructures();
  printk(KERN_INFO "itcImplInit: zoo=%lu\n",jiffies);
}


void itcImplExit(void) {
  itcExitStructures();
}
