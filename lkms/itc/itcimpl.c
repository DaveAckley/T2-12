#include "itcimpl.h"
#include <linux/delay.h>	    /* for msleep() */
#include <linux/jiffies.h>	    /* for time_before(), time_after() */
#include <linux/interrupt.h>	    /* for interrupt functions.. */
#include <linux/gpio.h>		    /* for gpio functions.. */

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

#define YY()              \
  XX(ET, 69, 68, 66, 67), \
  XX(SE, 26, 27, 45, 23), \
  XX(SW, 61, 10, 65, 22), \
  XX(WT, 81,  8, 11,  9), \
  XX(NW, 79, 60, 80, 78), \
  XX(NE, 49, 14, 50, 51) 

#define XX(DC,p1,p2,p3,p4) DIR_##DC
enum { YY(), DIR_MIN = DIR_ET, DIR_MAX = DIR_NE, DIR_COUNT };
#undef XX

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

static JiffyUnit globalLastActive = 0;

#define XX(DC,p1,p2,p3,p4) #DC
static const char * dirnames[DIR_COUNT] = { YY() };
#undef XX

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
static struct gpio pins[DIR_COUNT][4] = { YY() };
#undef XX

#define XX(DC,p1,p2,p3,p4) { .direction = DIR_##DC, .pins = pins[DIR_##DC] }
static ITCInfo itcInfo[DIR_COUNT] = { YY() };
#undef XX

static irq_handler_t itc_irq_handler(unsigned int irq, void *dev_id, struct pt_regs *regs)
{
  globalLastActive = jiffies;
  printk(KERN_INFO "itc_irq_handler: irq=%d\n", irq);
  return (irq_handler_t) IRQ_HANDLED;  // Announce that the IRQ has been handled correctly
}

void itcInitStructure(ITCInfo * itc)
{
  const char * dn = itcDirName(itc->direction);
  int i;
  int result;
  itc->state = sRESET;
  itc->resets = 1;
  itc->locksAttempted = 0;
  itc->locksAcquired = 0;
  itc->locksGranted = 0;
  itc->locksContested = 0;
  itc->lastActive = jiffies;

  printk(KERN_INFO "ITC init %s: IRQLK=%d, IGRLK=%d, ORQLK=%d, OGRLK=%d\n",
	 dn,
	 itc->pins[PIN_IRQLK].gpio,itc->pins[PIN_IGRLK].gpio,
	 itc->pins[PIN_ORQLK].gpio,itc->pins[PIN_OGRLK].gpio);

  for (i = PIN_IRQLK; i <= PIN_IGRLK; ++i) {
    IRQNumber * ip = (i == PIN_IRQLK) ? &itc->qIRQLK  : &itc->qIGRLK;
    *ip = gpio_to_irq(itc->pins[i].gpio);
    result = request_irq(*ip, (irq_handler_t) itc_irq_handler,
			 IRQF_TRIGGER_RISING | IRQF_TRIGGER_FALLING,
			 itc->pins[i].label,
			 NULL);
    printk(KERN_INFO "ITC %s: irq#=%d, result=%d\n",
	   itc->pins[i].label, *ip, result);
  }
}

void itcInitStructures(void) {

  /////
  /// First do global (full tile) inits

  int err;
  unsigned count = ARRAY_SIZE(pins)*ARRAY_SIZE(pins[0]);

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
        printk(KERN_INFO "ITC failed to allocate pin%3d: %d\n", g->gpio, err);
      } else {
        printk(KERN_INFO "ITC allocated pin%3d for %s\n", g->gpio, g->label); 
      }
    }
  }
#endif

  /////
  /// Now do local (per-ITC) inits
  {
    ITCDir i;
    for (i = DIR_MIN; i <= DIR_MAX; ++i) {
      BUG_ON(i != itcInfo[i].direction);  /* Assert we inited directions properly */
      itcInitStructure(&itcInfo[i]);
    }
  }
}

void itcExitStructure(ITCInfo * itc)
{
  const char * dn = itcDirName(itc->direction);
  free_irq(itc->qIRQLK,NULL);
  free_irq(itc->qIGRLK,NULL);
  printk(KERN_INFO "ITC exit %s\n", dn);
}

void itcExitStructures(void) {

  /////
  /// First do global (full tile) cleanup

  unsigned count = ARRAY_SIZE(pins)*ARRAY_SIZE(pins[0]);
  unsigned i;

  gpio_free_array(&pins[0][0], count);
  printk(KERN_INFO "ITC freed %d pins\n", count); 

  /////
  /// Now do local (per-itc) cleanup

  for (i = DIR_MIN; i <= DIR_MAX; ++i) {
    itcExitStructure(&itcInfo[i]);
  }
}

void check_timeouts(void)
{
  globalLastActive = jiffies;
  printk(KERN_INFO "itcThreadRunner: timeout %lu\n",globalLastActive);
}

/** @brief The ITC main timing loop
 *
 *  @param arg A void pointer available to pass data to the thread
 *  @return returns 0 if successful
 */
int itcThreadRunner(void *arg) {
  const int jiffyTimeout = 5*HZ;
   printk(KERN_INFO "itcThreadRunner: Started\n");
   while(!kthread_should_stop()){           // Returns true when kthread_stop() is called
      set_current_state(TASK_RUNNING);
      if (time_before(globalLastActive+jiffyTimeout, jiffies))
	check_timeouts();
      set_current_state(TASK_INTERRUPTIBLE);
      msleep(4);
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
