#include "itcimpl.h"
#include <linux/delay.h>	    /* for msleep() */
#include <linux/jiffies.h>	    /* for time_before(), time_after() */
#include <linux/interrupt.h>	    /* for interrupt functions.. */
#include <linux/gpio.h>		    /* for gpio functions.. */
#include <linux/random.h>	    /* for prandom_u32_max() */

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
       STATE_COUNT
};

/* Here is the ITC-to-GPIO mapping.  Each ITC uses four gpios, labeled
   IRQLK, IGRLK, ORQLK, and OGRLK.  */

#define YY()                       \
/*  DIR IRQLK IGRLK ORQLK OGRLK */ \
  XX(ET,  69,   68,   66,   67)    \
  XX(SE,  26,   27,   45,   23)    \
  XX(SW,  61,   10,   65,   22)    \
  XX(WT,  81,    8,   11,    9)    \
  XX(NW,  79,   60,   80,   78)    \
  XX(NE,  49,   14,   50,   51) 

#define XX(DC,p1,p2,p3,p4) DIR_##DC,
enum { YY() DIR_MIN = DIR_ET, DIR_MAX = DIR_NE, DIR_COUNT };
#undef XX

enum { PIN_MIN = 0, PIN_IRQLK = PIN_MIN, PIN_IGRLK, PIN_ORQLK, PIN_OGRLK, PIN_MAX = PIN_OGRLK, PIN_COUNT };

typedef unsigned long JiffyUnit;
typedef unsigned long ITCCounter;
typedef unsigned char ITCDir;
typedef unsigned char ITCState;
typedef unsigned int BitValue;
typedef int IRQNumber;
typedef struct itcInfo {
  const struct gpio * const pins;
  const ITCDir direction;
  BitValue pinStates[PIN_COUNT];
  ITCState state;
  ITCCounter fails;
  ITCCounter resets;
  ITCCounter locksAttempted;
  ITCCounter locksAcquired;
  ITCCounter locksGranted;
  ITCCounter locksContested;
  ITCCounter interruptsTaken;
  ITCCounter edgesMissed;
  JiffyUnit lastActive;
  JiffyUnit lastReported;
} ITCInfo;

typedef struct moduleData {
  JiffyUnit moduleLastActive;
  JiffyUnit nextShuffleTime;
  ITCDir shuffledIndices[DIR_COUNT];
  ITCInfo itcInfo[DIR_COUNT];
} ModuleData;

#define XX(DC,p1,p2,p3,p4) {  	       \
    { p1, GPIOF_DIR_IN, #DC "_IRQLK"}, \
    { p2, GPIOF_DIR_IN, #DC "_IGRLK"}, \
    { p3, GPIOF_DIR_OUT,#DC "_ORQLK"}, \
    { p4, GPIOF_DIR_OUT,#DC "_OGRLK"}, },
static struct gpio pins[DIR_COUNT][4] = { YY() };
#undef XX

static ModuleData md = {
  .moduleLastActive = 0,
  .nextShuffleTime = 0,
#define XX(DC,p1,p2,p3,p4) DIR_##DC,
  .shuffledIndices = { YY() },
#undef XX
#define XX(DC,p1,p2,p3,p4) { .direction = DIR_##DC, .pins = pins[DIR_##DC] },
  .itcInfo = { YY() }
#undef XX
};

#define XX(DC,p1,p2,p3,p4) #DC,
static const char * dirnames[DIR_COUNT] = { YY() };
#undef XX

const char * itcDirName(ITCDir d)
{
  if (d > DIR_MAX) return "(Illegal)";
  return dirnames[d];
}
  
void shuffleIndices(void) {
  ITCDir i;
  for (i = DIR_MAX; i > 0; --i) {
    int j = prandom_u32_max(i+1); /* generates 0..DIR_MAX down to 0..1 */
    if (i != j) {
      ITCDir tmp = md.shuffledIndices[i];
      md.shuffledIndices[i] = md.shuffledIndices[j];
      md.shuffledIndices[j] = tmp;
    }
  }
}

inline void shuffleIndicesOccasionally(void) {
  if (unlikely(time_after(jiffies,md.nextShuffleTime))) {
    shuffleIndices();
    md.nextShuffleTime = jiffies + prandom_u32_max(HZ * 60) + 1; /* half a min on avg */
  }
}

static irq_handler_t itc_irq_edge_handler(ITCInfo * itc, unsigned pin, unsigned value, unsigned int irq)
{
  itc->lastActive = md.moduleLastActive = jiffies;
  itc->interruptsTaken++;
  if (unlikely(value == itc->pinStates[pin]))
    itc->edgesMissed++;
  else
    itc->pinStates[pin] = value;
  return (irq_handler_t) IRQ_HANDLED;
}

#define XX(DC,p1,p2,p3,p4) ZZ(DC,_IRQLK) ZZ(DC,_IGRLK)
#define ZZ(DC,suf)                                                                                  \
static irq_handler_t itc_irq_handler##DC##suf(unsigned int irq, void *dev_id, struct pt_regs *regs) \
{                                                                                                   \
  return itc_irq_edge_handler(&md.itcInfo[DIR_##DC],                                                \
                              PIN##suf,                                                             \
                              gpio_get_value(md.itcInfo[DIR_##DC].pins[PIN##suf].gpio),             \
			      irq);	                                                            \
}
YY()
#undef ZZ
#undef XX

void itcInitStructure(ITCInfo * itc)
{
  const char * dn = itcDirName(itc->direction);
  itc->state = sFAILED;
  itc->resets = 1;
  itc->locksAttempted = 0;
  itc->locksAcquired = 0;
  itc->locksGranted = 0;
  itc->locksContested = 0;
  itc->lastActive = jiffies;
  itc->lastReported = jiffies-1;

  printk(KERN_INFO "ITC init %s: IRQLK=%d, IGRLK=%d, ORQLK=%d, OGRLK=%d\n",
	 dn,
	 itc->pins[PIN_IRQLK].gpio,itc->pins[PIN_IGRLK].gpio,
	 itc->pins[PIN_ORQLK].gpio,itc->pins[PIN_OGRLK].gpio);
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
      BUG_ON(i != md.itcInfo[i].direction);  /* Assert we inited directions properly */
      itcInitStructure(&md.itcInfo[i]);
    }
  }

  /// Now install irq handlers for everybody

#define ZZ(DC,suf) { 				                              \
    ITCInfo * itc = &md.itcInfo[DIR_##DC];                                    \
    const struct gpio * gp = &itc->pins[PIN##suf];                            \
    int result;                                                               \
    IRQNumber in = gpio_to_irq(gp->gpio);                                     \
    result = request_irq(in,                                                  \
			 (irq_handler_t) itc_irq_handler##DC##suf,            \
			 IRQF_TRIGGER_RISING | IRQF_TRIGGER_FALLING,          \
			 gp->label,                                           \
			 NULL);                                               \
    printk(KERN_INFO "ITC %s: irq#=%d, result=%d\n", gp->label, in, result);  \
  }
#define XX(DC,p1,p2,p3,p4) ZZ(DC,_IRQLK) ZZ(DC,_IGRLK)
    YY()
#undef ZZ
#undef XX
}

void itcExitStructure(ITCInfo * itc)
{
  const char * dn = itcDirName(itc->direction);
  free_irq(gpio_to_irq(itc->pins[PIN_IRQLK].gpio),NULL);
  free_irq(gpio_to_irq(itc->pins[PIN_IGRLK].gpio),NULL);
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
    itcExitStructure(&md.itcInfo[i]);
  }
}

void check_timeouts(void)
{
  int i;
  md.moduleLastActive = jiffies;

  printk(KERN_INFO "ITC timeout %lu\n", md.moduleLastActive);
  for (i = DIR_MIN; i <= DIR_MAX; ++i) {
    if (md.itcInfo[i].lastReported == md.itcInfo[i].lastActive) continue;
    printk(KERN_INFO "ITC %s: s=%d, f=%lu, r=%lu, at=%lu, ac=%lu, gr=%lu, co=%lu, it=%lu, em=%lu\n",
	   itcDirName(md.itcInfo[i].direction),
	   md.itcInfo[i].state,
	   md.itcInfo[i].fails,
	   md.itcInfo[i].resets,
	   md.itcInfo[i].locksAttempted,
	   md.itcInfo[i].locksAcquired,
	   md.itcInfo[i].locksGranted,
	   md.itcInfo[i].locksContested,
	   md.itcInfo[i].interruptsTaken,
	   md.itcInfo[i].edgesMissed
	   );
    md.itcInfo[i].lastReported = md.itcInfo[i].lastActive;
  }
}

#define SS()        \
  XX(sRESET,  1,1)  \
  XX(sIDLE,   0,0)  \
  XX(sTAKE,   1,0)  \
  XX(sTAKEN,  1,1)  \
  XX(sGIVE,   0,1)  \
  XX(sGIVEN,  0,1)  \
  XX(sSYNC11, 1,1)  \
  XX(sSYNC01, 0,1)  \
  XX(sSYNC00, 0,0)  \
  XX(sFAILED, 1,1)

#define XX(state,orqlk,ogrlk) (((orqlk)<<1)|((ogrlk)<<0)),
const unsigned char outputsForState[STATE_COUNT] = { SS() };
#undef XX

#define XX(state,orqlk,ogrlk) #state,
const const char * stateNames[STATE_COUNT] = { SS() };
#undef XX

const char * getStateName(ITCState s) {
  if (s >= STATE_COUNT) return "<INVALID>";
  return stateNames[s];
 }

void setState(ITCInfo * itc, ITCState newState) {
  unsigned orqv = outputsForState[newState]>>1;
  unsigned ogrv = outputsForState[newState]&1;
  if (newState == sRESET) ++itc->resets;
  itc->state = newState;
  gpio_set_value(itc->pins[PIN_ORQLK].gpio,orqv);
  gpio_set_value(itc->pins[PIN_OGRLK].gpio,ogrv);
  printk(KERN_INFO "ITC %s: newstate=%s(%d), O%d%d, I%d%d\n",
	 itcDirName(itc->direction),
	 getStateName(itc->state),itc->state,
	 gpio_get_value(itc->pins[PIN_ORQLK].gpio),
	 gpio_get_value(itc->pins[PIN_OGRLK].gpio),
	 gpio_get_value(itc->pins[PIN_IRQLK].gpio),
	 gpio_get_value(itc->pins[PIN_IGRLK].gpio));
}

#define SIC(state,irqlk,igrlk) (((state)<<2)|((irqlk)<<1)|((igrlk)<<0))
void updateState(ITCInfo * itc) {
  unsigned stateInput;
  ITCState nextState = sFAILED;
  // Read input pins
  itc->pinStates[PIN_IRQLK] = gpio_get_value(itc->pins[PIN_IRQLK].gpio);
  itc->pinStates[PIN_IGRLK] = gpio_get_value(itc->pins[PIN_IGRLK].gpio);

  stateInput = SIC(itc->state,itc->pinStates[PIN_IRQLK],itc->pinStates[PIN_IGRLK]);
  switch (stateInput) {
  case SIC(sRESET,0,0): nextState = sRESET; break;
  case SIC(sRESET,0,1): nextState = sRESET; break;
  case SIC(sRESET,1,0): nextState = sRESET; break;
  case SIC(sRESET,1,1): nextState = sSYNC11; break;

  case SIC(sSYNC11,0,0): nextState = sRESET; break;
  case SIC(sSYNC11,0,1): nextState = sRESET; break;
  case SIC(sSYNC11,1,0): nextState = sRESET; break;
  case SIC(sSYNC11,1,1): nextState = sSYNC01; break;

  case SIC(sSYNC01,0,0): nextState = sRESET; break;
  case SIC(sSYNC01,0,1): nextState = sSYNC00; break;
  case SIC(sSYNC01,1,0): nextState = sRESET; break;
  case SIC(sSYNC01,1,1): nextState = sSYNC01; break;

  case SIC(sSYNC00,0,0): nextState = sIDLE; break;
  case SIC(sSYNC00,0,1): nextState = sSYNC00; break;
  case SIC(sSYNC00,1,0): nextState = sRESET; break;
  case SIC(sSYNC00,1,1): nextState = sRESET; break;

  }
  if (nextState == sFAILED) {
    ++itc->fails;
    setState(itc,sRESET);
  } else if (nextState != itc->state) {
    itc->lastActive = jiffies;
    setState(itc,nextState);
  }
}

void updateStates(void) {
  ITCDir i;
  for (i = 0; i < DIR_COUNT; ++i) {
    ITCDir idx = md.shuffledIndices[i];
    //    printk(KERN_INFO "update state %d/%d\n",i,idx);
    updateState(&md.itcInfo[idx]);
  }
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
    shuffleIndicesOccasionally();
    updateStates();
    if (time_before(md.moduleLastActive + jiffyTimeout, jiffies))
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
