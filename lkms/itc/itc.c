/*
 * Copyright (C) 2019 The T2 Tile Project
 * 
 * Based on itcinit.c and itcimpl.c, where were:
 *
 * Copyright (C) 2017 The Regents of the University of New Mexico
 *
 * This software is licensed under the terms of the GNU General Public
 * License version 2, as published by the Free Software Foundation, and
 * may be copied, distributed, and modified under those terms.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 */

#include "itc.h"
#include "ruleset.h"
#include "RULES.h"

#define  DEVICE_NAME0 "itc!locks"  ///< The device will appear at /dev/itc/locks/
#define  DEVICE_NAME1 "itc!lockevents"  ///< The device will appear at /dev/itc/lockevents
#define  CLASS_NAME  "itccls"     ///< The device class -- this is a character device driver

void setState(ITCInfo * itc, ITCState newState) ; // FORWARD
void updateState(ITCInfo * itc, bool timeout) ;   // FORWARD

bool isActiveWithin(ITCInfo * itc, int jiffyCount)
{
  return time_after(itc->lastActive + jiffyCount, jiffies);
}

/* GENERATE CURRENT DIRS IN STATE TABLE */
u8 dirsInState[STATE_COUNT] = {
#define RSE(forState,output,settlement,...) RS(forState,forState,output,settlement,__VA_ARGS__)
#define RSN(forState,output,settlement,...) RS(forState,_,output,settlement,__VA_ARGS__)
#define RS(forState,ef,output,settlement,...) 0,
  ALLRULESMACRO()
};
#undef RS
#undef RSE
#undef RSN

/* GENERATE SETTLEMENT ACCESSORS */
#define RSE(forState,output,settlement,...) RS(forState,forState,output,settlement,__VA_ARGS__)
#define RSN(forState,output,settlement,...) RS(forState,_,output,settlement,__VA_ARGS__)
#define RS(forState,ef,output,settlement,...) (((settlement)==YY()) ? dirsInState[forState] : 0)|
u32 getSettlementValue(SettlementState ss) {
  switch(ss) {
#define YY() LOCK_UNREADY
  case LOCK_UNREADY: return ALLRULESMACRO() 0;
#undef YY
#define YY() LOCK_AVAILABLE
  case LOCK_AVAILABLE: return ALLRULESMACRO() 0;
#undef YY
#define YY() LOCK_UNSETTLED
  case LOCK_UNSETTLED: return ALLRULESMACRO() 0;
#undef YY
#define YY() LOCK_SETTLED
  case LOCK_SETTLED: return ALLRULESMACRO() 0;
#undef YY
  default: return 0;
  }
}
#undef RS
#undef RSE
#undef RSN


/* GENERATE STATE ENTRY COUNTERS */
#define RSE(forState,output,settlement,...) RS(forState,forState,output,settlement,__VA_ARGS__)
#define RSN(forState,output,settlement,...) RS(forState,_,output,settlement,__VA_ARGS__)
#define RS(forState,ef,output,settlement,...) 0,
u32 timesStateEntered[STATE_COUNT] = {
  ALLRULESMACRO()
};
#undef RS
#undef RSE
#undef RSN


/* GENERATE STATE NAMES */
#define RSE(forState,output,settlement,...) RS(forState,forState,output,settlement,__VA_ARGS__)
#define RSN(forState,output,settlement,...) RS(forState,_,output,settlement,__VA_ARGS__)
#define RS(forState,ef,output,settlement,...) #forState,
const char * stateNames[STATE_COUNT] = { 
  ALLRULESMACRO()
};
#undef RS
#undef RSE
#undef RSN

const char * getStateName(ITCState s) {
  if (s >= STATE_COUNT) return "<INVALID>";
  return stateNames[s];
 }

/* GENERATE STATE->output table */
#define RSE(forState,output,settlement,...) RS(forState,forState,output,settlement,__VA_ARGS__)
#define RSN(forState,output,settlement,...) RS(forState,_,output,settlement,__VA_ARGS__)
#define RS(forState,ef,output,settlement,...) OUTPUT_VALUE_##output,
const u8 outputsForState[STATE_COUNT] = {
  ALLRULESMACRO()
};
#undef RS
#undef RSE
#undef RSN

/* GENERATE STATE->settlement table */
#define RSE(forState,output,settlement,...) RS(forState,forState,output,settlement,__VA_ARGS__)
#define RSN(forState,output,settlement,...) RS(forState,_,output,settlement,__VA_ARGS__)
#define RS(forState,ef,output,settlement,...) settlement,
const u8 settlementOfState[STATE_COUNT] = {
  ALLRULESMACRO()
};
#undef RS
#undef RSE
#undef RSN

typedef ITCState ITCEntryFunction(struct itcInfo*,unsigned stateInput);

/* GENERATE ENTRY FUNCTION DECLARATIONS */
#define RSE(forState,output,...) extern ITCEntryFunction entryFunction_##forState;
#define RSN(forState,output,...) 
  ALLRULESMACRO()
#undef RSE
#undef RSN

/* GENERATE STATE->entry function pointers */
#define RSE(forState,output,...) entryFunction_##forState,
#define RSN(forState,output,...) NULL,
ITCEntryFunction *(entryFuncsForState[STATE_COUNT]) = {
  ALLRULESMACRO()
};
#undef RSE
#undef RSN

/* GENERATE PER-STATE RULESETS */
#define RSE(forState,output,settlement,...) RS(forState,forState,output,settlement,__VA_ARGS__)
#define RSN(forState,output,settlement,...) RS(forState,_,output,settlement,__VA_ARGS__)
#define RS(forState,ef,output,settlement,...) const Rule ruleSet_##forState[] = { __VA_ARGS__ };
  ALLRULESMACRO()
#undef RS
#undef RSE
#undef RSN

/* GENERATE STATE->RULESET DISPATCH TABLE */
#define RSE(forState,output,settlement,...) RS(forState,forState,output,settlement,__VA_ARGS__)
#define RSN(forState,output,settlement,...) RS(forState,_,output,settlement,__VA_ARGS__)
#define RS(forState,ef,output,...) ruleSet_##forState,
const Rule *(ruleSetDispatchTable[STATE_COUNT]) = {
  ALLRULESMACRO()
};
#undef RS
#undef RSE
#undef RSN

#define XX(DC,fr,p1,p2,p3,p4) {  	                           \
    { p1, GPIOF_IN|GPIOF_EXPORT_DIR_FIXED,          #DC "_IRQLK"}, \
    { p2, GPIOF_IN|GPIOF_EXPORT_DIR_FIXED,          #DC "_IGRLK"}, \
    { p3, GPIOF_OUT_INIT_LOW|GPIOF_EXPORT_DIR_FIXED,#DC "_ORQLK"}, \
    { p4, GPIOF_OUT_INIT_LOW|GPIOF_EXPORT_DIR_FIXED,#DC "_OGRLK"}, },
static struct gpio pins[DIR_COUNT][4] = { DIRDATAMACRO() };
#undef XX

static ITCModuleState S = {
  .moduleLastActive = 0,
  .userRequestTime = 0,
  .userLockset = 0,
  .userRequestActive = 0,
  .majorNumber = -1,
  .numberOpens = 0,
  .minorsBuilt = 0,
  .itcClass = NULL,
  .itcThreadRunnerTask = 0,
  // Initted in initModuleState below
  // .userWaitQ;  
  // .mdLock;       
  // .itc_mutex;

  
#define XX(DC,fr,p1,p2,p3,p4) { .direction = DIR_##DC, .isFred = fr, .pins = pins[DIR_##DC] },
  .itcInfo = { DIRDATAMACRO() }
#undef XX
};

#define XX(DC,fr,p1,p2,p3,p4) #DC,
static const char * dirnames[DIR_COUNT] = { DIRDATAMACRO() };
#undef XX

///////////////////// LOCKEVENT TRACING STUFF

static void initLockEventState(ITCLockEventState* lec) {
  lec->mStartTime = 0;
  lec->mShiftDistance = 10; /* divide by 1024 -> ~usec resolution */
  INIT_KFIFO(lec->mEvents);
  mutex_init(&lec->mLockEventReadMutex);
  printk(KERN_INFO "ILES kfifo_len(%d) kfifo_avail(%d)\n",
         kfifo_len(&lec->mEvents),
         kfifo_avail(&lec->mEvents)
         );
}

static int startLockEventTrace(ITCLockEventState* lec) {
  int error;

  if ( (error = mutex_lock_interruptible(&lec->mLockEventReadMutex)) ) return error;  
  lec->mStartTime = ktime_get_raw_fast_ns();  /* Init time before making room in kfifo! */
  kfifo_reset_out(&lec->mEvents);             /* Flush kfifo from the read side */
  mutex_unlock(&lec->mLockEventReadMutex);

  return 0;
}

#define ADD_LOCK_EVENT(event)                                             \
  do {                                                                    \
   if (kfifo_avail(&S.mLockEventState.mEvents) >= sizeof(ITCLockEvent))   \
     addLockEvent(&S.mLockEventState,(event));                            \
  } while(0)   

/*MUST BE CALLED ONLY AT INTERRUPT LEVEL OR WITH INTERRUPTS DISABLED*/
static void addLockEvent(ITCLockEventState* lec, u32 event) {
  ITCLockEvent tmp;
  u64 now = ktime_get_raw_fast_ns() - lec->mStartTime;
  tmp.time = (u32) (now>>lec->mShiftDistance); // Cut down to u24
  
  if (kfifo_avail(&lec->mEvents) >= 2*sizeof(ITCLockEvent)) tmp.event = event;
  else tmp.event = makeSpecLockEvent(LET_SPEC_QGAP);

  kfifo_put(&lec->mEvents, tmp);
}

#define ADD_LOCK_EVENT_IRQ(event)                                          \
  do {                                                                     \
    if (kfifo_avail(&S.mLockEventState.mEvents) >= sizeof(ITCLockEvent)) { \
      unsigned long flags;                                                 \
      local_irq_save(flags);                                               \
      addLockEvent(&S.mLockEventState,(event));                            \
      local_irq_restore(flags);                                            \
    }                                                                      \
  } while(0)

const char * itcDirName(ITCDir d)
{
  if (d > DIR_MAX) return "(Illegal)";
  return dirnames[d];
}
  
void itcIteratorInitialize(ITCIterator * itr, ITCIteratorUseCount avguses) {
  int i;
  BUG_ON(!itr);
  BUG_ON(avguses <= 0);
  BUG_ON((avguses<<1) <= 0);
  itr->m_averageUsesPerShuffle = avguses;
  for (i = 0; i < DIR_COUNT; ++i) itr->m_indices[i] = i;
  itcIteratorShuffle(itr);
}

void itcIteratorShuffle(ITCIterator * itr) {
  ITCDir i;
  BUG_ON(!itr);
  itr->m_usesRemaining = 
    prandom_u32_max(itr->m_averageUsesPerShuffle<<1) + 1; /* max is double avg, given uniform random */

  for (i = DIR_MAX; i > 0; --i) {
    int j = prandom_u32_max(i+1); /* generates 0..DIR_MAX down to 0..1 */
    if (i != j) {
      ITCDir tmp = itr->m_indices[i];
      itr->m_indices[i] = itr->m_indices[j];
      itr->m_indices[j] = tmp;
    }
  }

  printk(KERN_DEBUG "ITC %p iterator order is %d%d%d%d%d%d for next %d uses\n",
         itr,
         itr->m_indices[0],
         itr->m_indices[1],
         itr->m_indices[2],
         itr->m_indices[3],
         itr->m_indices[4],
         itr->m_indices[5],
         itr->m_usesRemaining
         );
}

static irq_handler_t itc_irq_edge_handler(ITCInfo * itc, unsigned pin, unsigned value, unsigned int irq)
{
  itc->interruptsTaken++;
  if (unlikely(value == itc->pinStates[pin])) {
    if (pin < 2)
      itc->edgesMissed[pin]++;
  } else {
    itc->pinStates[pin] = value;
    ADD_LOCK_EVENT(makePinLockEvent(itc->direction,pin,value));
  }
  updateState(itc,false);
  return (irq_handler_t) IRQ_HANDLED;
}

#define XX(DC,fr,p1,p2,p3,p4) ZZ(DC,_IRQLK) ZZ(DC,_IGRLK)
#define ZZ(DC,suf)                                                                                  \
static irq_handler_t itc_irq_handler##DC##suf(unsigned int irq, void *dev_id, struct pt_regs *regs) \
{                                                                                                   \
  return itc_irq_edge_handler(&S.itcInfo[DIR_##DC],                                                 \
                              PIN##suf,                                                             \
                              gpio_get_value(S.itcInfo[DIR_##DC].pins[PIN##suf].gpio),              \
			      irq);	                                                            \
}
DIRDATAMACRO()
#undef ZZ
#undef XX

static void itcInitITC(ITCInfo * itc)
{
  int i;

  itc->interruptsTaken = 0;
  itc->edgesMissed[0] = 0;
  itc->edgesMissed[1] = 0;
  itc->lastActive = jiffies;
  itc->lastReported = jiffies-1;

  // Init to opposite of pin states to help edge interrupts score right?
  itc->pinStates[PIN_IRQLK] = !gpio_get_value(itc->pins[PIN_IRQLK].gpio);
  itc->pinStates[PIN_IGRLK] = !gpio_get_value(itc->pins[PIN_IGRLK].gpio);

  // Set up initial state
  setState(itc,sFAILED);

  // Clear state counters after setting initial state
  for (i = 0; i < STATE_COUNT; ++i)
    itc->enteredCount[i] = 0;

  // Set up magic wait counters for decelerating connection attempts
  itc->magicWaitTimeouts = 0;
  itc->magicWaitTimeoutLimit = 1;

}

static void itcExitITC(ITCInfo * itc)
{
  const char * dn = itcDirName(itc->direction);
  free_irq(gpio_to_irq(itc->pins[PIN_IRQLK].gpio),NULL);
  free_irq(gpio_to_irq(itc->pins[PIN_IGRLK].gpio),NULL);
  printk(KERN_INFO "ITC exit %s\n", dn);
}

static void itcExitGPIOs(void) ;

static void itcInitGPIOs(void) {

  /////
  /// First do global (full tile) inits

  int err;
  unsigned count = ARRAY_SIZE(pins)*ARRAY_SIZE(pins[0]);

  // Init the user context iterator, with very rare shuffling
  itcIteratorInitialize(&S.userContextIterator, 100000);

  printk(KERN_INFO "ITC PREFREEING PINS??\n");
  itcExitGPIOs();

  printk(KERN_INFO "ITC allocating %d pins\n", count);

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

  /////
  /// Now do local (per-ITC) inits
  {
    ITCDir i;
    for (i = DIR_MIN; i <= DIR_MAX; ++i) {
      BUG_ON(i != S.itcInfo[i].direction);  /* Assert we inited directions properly */
      itcInitITC(&S.itcInfo[i]);
    }
  }
}

static void itcInitGPIOInterrupts(void) {

  /// Now install irq handlers for everybody

#define ZZ(DC,suf) { 				                              \
    ITCInfo * itc = &S.itcInfo[DIR_##DC];                                     \
    const struct gpio * gp = &itc->pins[PIN##suf];                            \
    int result;                                                               \
    IRQNumber in = gpio_to_irq(gp->gpio);                                     \
    result = request_irq(in,                                                  \
			 (irq_handler_t) itc_irq_handler##DC##suf,            \
			 IRQF_TRIGGER_RISING | IRQF_TRIGGER_FALLING,          \
			 gp->label,                                           \
			 NULL);                                               \
    if (result)                                                               \
      printk(KERN_INFO "ITC %s: irq#=%d, result=%d\n", gp->label, in, result);\
    else                                                                      \
      printk(KERN_INFO "ITC %s: OK irq#=%d for gpio=%d\n", gp->label, in, gp->gpio); \
  }
#define XX(DC,fr,p1,p2,p3,p4) ZZ(DC,_IRQLK) ZZ(DC,_IGRLK)
    DIRDATAMACRO()
#undef ZZ
#undef XX
}

static void itcExitGPIOs(void) {

  /////
  /// First do global (full tile) cleanup

  unsigned count = ARRAY_SIZE(pins)*ARRAY_SIZE(pins[0]);

  gpio_free_array(&pins[0][0], count);
  printk(KERN_INFO "ITC freed %d pins\n", count); 
}

static void itcExitGPIOInterrupts(void) {
  unsigned i;

  /////
  /// Now do local (per-itc) cleanup

  for (i = DIR_MIN; i <= DIR_MAX; ++i) {
    itcExitITC(&S.itcInfo[i]);
  }
}

static void addEventCurrentLockState(unsigned ofState) {
  if (ofState <= 9) {
    unsigned long flags;
    local_irq_save(flags);
    if (kfifo_avail(&S.mLockEventState.mEvents) < 3*sizeof(ITCLockEvent))  
      ADD_LOCK_EVENT(makeSpecLockEvent(LET_SPEC_QGAP));
    else {
      ADD_LOCK_EVENT(makeSpecLockEvent(LET_SPEC_CLS0 + ofState));
      ADD_LOCK_EVENT(makeCurrentLockEvent(dirsInState[ofState]));
    }
    local_irq_restore(flags);
  }
}

static void updateEnabling(unsigned bareLockset) {
  unsigned long flags;
  spin_lock_irqsave(&S.mdLock, flags);    // Grab mdLock

  for (itcIteratorStart(&S.userContextIterator); // CRITICAL SECTION: mdLock
       itcIteratorHasNext(&S.userContextIterator);// CRITICAL SECTION: mdLock
       ) {
    ITCDir idx = itcIteratorGetNext(&S.userContextIterator); // CRITICAL SECTION: mdLock
    ITCInfo * itc = &S.itcInfo[idx];        // CRITICAL SECTION: mdLock
    unsigned itcbit = 1<<idx;               // CRITICAL SECTION: mdLock
    bool enable = bareLockset & itcbit;     // CRITICAL SECTION: mdLock
    if (enable) {                           // CRITICAL SECTION: mdLock
      if (dirsInState[sDISABLED] & itcbit)    // (enable only affects disabled itcs)
        setState(itc, sRESET);              // CRITICAL SECTION: mdLock
    } else {                                // CRITICAL SECTION: mdLock
      setState(itc,sDISABLED);               // (but disable nukes all states)
    }                                       // CRITICAL SECTION: mdLock
  }                                         // CRITICAL SECTION: mdLock
  spin_unlock_irqrestore(&S.mdLock, flags); // Free mdLock
}

// itcInterpretCommandByte
// Returns:
//
//  o -ENODEV if currently unimplemented code is encountered
//
//  o -EINVAL if either of the top two bits of lockset are non-zero,
//     and in this case the current lock posture remains unchanged
//
//  o -EBUSY if any requested locks were already given to far side,
//    and in this case any locks that we are holding will be released
//
//  o 0 if we successfully took all requested locks and released any
//    others that we may have been holding
static ssize_t itcInterpretCommandByte(u8 cmd, bool waitForIt)
{
  unsigned long flags;
  unsigned startState, destState, untouchedState;
  unsigned locksetCmd = (cmd & LOCKSET_CMD_MASK);
  unsigned bareLockset = (cmd & ~LOCKSET_CMD_MASK);

  if (locksetCmd == LOCKSET_CMD_VALUE_TRY) {

    ADD_LOCK_EVENT_IRQ(makeSpecLockEvent(LET_SPEC_UTRY));  // Next user lock req is uTRY
    startState = sIDLE;                                    // We should be coming from sIDLE
    destState = sTAKEN;                                    // and settling on sTAKEN
    untouchedState = sGIVEN;                               // And sGIVEN should be untouched

  } else if (locksetCmd == LOCKSET_CMD_VALUE_FREE) {

    ADD_LOCK_EVENT_IRQ(makeSpecLockEvent(LET_SPEC_UFRE));  // Next user lock req is uFREE
    startState = sGIVEN;                                   // We should be coming from sGIVEN
    destState = sIDLE;                                     // and settling on sIDLE
    untouchedState = sTAKEN;                               // And sTAKEN should be untouched

  } else if (locksetCmd == LOCKSET_CMD_VALUE_DROP) {

    ADD_LOCK_EVENT_IRQ(makeSpecLockEvent(LET_SPEC_UDRP));  // Next user lock req is uDROP
    startState = sTAKEN;                                   // We should be coming from sTAKEN
    destState = sIDLE;                                     // and settling on sIDLE
    untouchedState = sGIVEN;                               // And sGIVEN should be untouched

  } else if (locksetCmd == LOCKSET_CMD_VALUE_ENABLE) {

    ADD_LOCK_EVENT_IRQ(makeSpecLockEvent(LET_SPEC_UENB));  // Next user lock req is 'uENABLE'
    addEventCurrentLockState(sDISABLED);                   // We'll be affecting this
    updateEnabling(bareLockset);                           // Go do it
    addEventCurrentLockState(sDISABLED);                   // There's the result
    return 0;                                              // Enabling always succeeds

  } else                 // (Can't happen since all locksetCmds now defined)
    return -EINVAL;

  ADD_LOCK_EVENT_IRQ(makeUserLockEvent(bareLockset)); // Next user locks req

  if (getSettlementValue(LOCK_UNREADY) & bareLockset)
    return -ENXIO;
  
  if (dirsInState[untouchedState] & bareLockset)      // Check for conflicts
    return -EBUSY;   // Can't take what is given or free what is taken

  addEventCurrentLockState(startState);

  if ((bareLockset & dirsInState[destState]) == bareLockset) // If already have all asked for
    return 0;                                                // You're welcome

  // First set up our request
  spin_lock_irqsave(&S.mdLock, flags);    // Grab mdLock
  S.userRequestTime = jiffies;            // CRITICAL SECTION: mdLock
  S.moduleLastActive = jiffies-100;       // CRITICAL SECTION: mdLock
  S.userLockset = cmd;                    // CRITICAL SECTION: mdLock
  S.userRequestActive = 1;                // CRITICAL SECTION: mdLock
  S.userRequestStatus = 0;                // CRITICAL SECTION: mdLock
  // Hold mdlock for whole loop gah.
  for (itcIteratorStart(&S.userContextIterator); // CRITICAL SECTION: mdLock
       itcIteratorHasNext(&S.userContextIterator);// CRITICAL SECTION: mdLock
       ) {
    ITCDir idx = itcIteratorGetNext(&S.userContextIterator); // CRITICAL SECTION: mdLock
    ITCInfo * itc = &S.itcInfo[idx];        // CRITICAL SECTION: mdLock
    
    updateState(itc,false);                 // CRITICAL SECTION: mdLock
  }
  spin_unlock_irqrestore(&S.mdLock, flags); // Free mdLock

  // Now kick the kthread since this is our initiative
  if (S.itcThreadRunnerTask)
    wake_up_process(S.itcThreadRunnerTask);

  // Now wait until our request has been handled

  if (waitForIt) {
    while (S.userRequestActive) {
      wait_event_interruptible(S.userWaitQ, !S.userRequestActive);
    }
  }

  addEventCurrentLockState(destState);

  return 0;      // 'Operation Worked'..
}

#if 0
static int itcGetCurrentLockInfo(u8 * buffer, int len)
{
  int i;

  if (len < 0) return -EINVAL;
  if (len == 0) return 0;

  if (len > 6) len = 6;

  for (i = 0; i < len; ++i) buffer[i] = 0;
  
  for (i = 0; i < 6; ++i) {  /*Note: Not using ITCIterator*/
    ITCDir idx = i;
    ITCInfo * itc = &S.itcInfo[idx];
    u8 bit = 1<<idx;
    switch (len) {
    default:
    case 6: if (itc->state == sRESET) buffer[5] |= bit;
    case 5: if (itc->state == sFAILED) buffer[4] |= bit;
    case 4: if (itc->state == sIDLE) buffer[3] |= bit;
    case 3: if (itc->state == sGIVEN) buffer[2] |= bit;
    case 2: if (itc->state == sTAKE ||
                itc->state == sRACE ||
                itc->state == sSYNC01) buffer[1] |= bit;
    case 1: if (itc->state == sTAKEN) buffer[0] |= bit;
    case 0: break;
    }
  }

  return len;
}
#endif


void make_reports(void)
{
  int i;

  for (i = DIR_MIN; i <= DIR_MAX; ++i) {
    if (S.itcInfo[i].lastReported == S.itcInfo[i].lastActive) continue;
#ifdef REPORT_LOCK_STATE_CHANGES
    printk(KERN_INFO "ITC %s(%s): o%d%d i%d%d, f%lu, r%lu, at%lu, ac%lu, gr%lu, co%lu, it%lu, emQ%lu, emG%lu\n",
	   itcDirName(S.itcInfo[i].direction),
	   getStateName(S.itcInfo[i].state),
	   S.itcInfo[i].pinStates[PIN_ORQLK],
	   S.itcInfo[i].pinStates[PIN_OGRLK],
	   S.itcInfo[i].pinStates[PIN_IRQLK],
	   S.itcInfo[i].pinStates[PIN_IGRLK],
	   S.itcInfo[i].enteredCount[sFAILED],
	   S.itcInfo[i].enteredCount[sRESET],
	   S.itcInfo[i].enteredCount[sTAKE],
	   S.itcInfo[i].enteredCount[sTAKEN],
	   S.itcInfo[i].enteredCount[sGIVEN],
	   S.itcInfo[i].enteredCount[sRACE],
	   S.itcInfo[i].interruptsTaken,
	   S.itcInfo[i].edgesMissed[0],
	   S.itcInfo[i].edgesMissed[1]
	   );
#endif
    S.itcInfo[i].lastReported = S.itcInfo[i].lastActive;
  }
}

static inline void userRequestDone(s32 status) {
  if (S.userRequestActive) {
    ADD_LOCK_EVENT_IRQ(makeSpecLockEvent(LET_SPEC_URDO));
    S.userRequestActive = 0;
    S.userRequestStatus = status;
    wake_up_interruptible(&S.userWaitQ);
  }
}

void setState(ITCInfo * itc, ITCState newState) {
  if (itc->state != newState) {

    dirsInState[itc->state] &= ~(1<<itc->direction); /*clear previous state*/
    itc->state = newState;
    dirsInState[itc->state] |= 1<<itc->direction; /*set current state*/
    ++itc->enteredCount[newState];

    ADD_LOCK_EVENT(makeStateLockEvent(itc->direction,newState));

    {
      const BitValue newval = (outputsForState[newState]>>1)&1;
      if (itc->pinStates[PIN_ORQLK] != newval) {
        itc->pinStates[PIN_ORQLK] = newval;
        ADD_LOCK_EVENT(makePinLockEvent(itc->direction,PIN_ORQLK,newval));
      }
    }
    {
      const BitValue newval = (outputsForState[newState]>>0)&1;
      if (itc->pinStates[PIN_OGRLK] != newval) {
        itc->pinStates[PIN_OGRLK] = newval;
        ADD_LOCK_EVENT(makePinLockEvent(itc->direction,PIN_OGRLK,newval));
      }
    }

    itc->lastActive = S.moduleLastActive = jiffies;

    if (0==getSettlementValue(LOCK_UNSETTLED)) {
      ADD_LOCK_EVENT_IRQ(makeSpecLockEvent(LET_SPEC_ALST));
      userRequestDone(S.userLockset);
    } else
      wake_up_process(S.itcThreadRunnerTask); // Look for more consequences?
  }
  gpio_set_value(itc->pins[PIN_ORQLK].gpio,itc->pinStates[PIN_ORQLK]);
  gpio_set_value(itc->pins[PIN_OGRLK].gpio,itc->pinStates[PIN_OGRLK]);
}

void updateState(ITCInfo * itc,bool istimeout) {
  unsigned stateInput;
  ITCState nextState = sFAILED;
  const Rule * rulep;
  unsigned activeTry = 0;
  unsigned activeFree = 0;

  if (S.userRequestActive) {
    unsigned locksetCmd = S.userLockset & LOCKSET_CMD_MASK;
    unsigned affected = (S.userLockset>>itc->direction)&1;
    if (locksetCmd == LOCKSET_CMD_VALUE_TRY)
      activeTry = affected;
    else if (locksetCmd == LOCKSET_CMD_VALUE_FREE
             || locksetCmd == LOCKSET_CMD_VALUE_DROP)
      activeFree = affected;
  }

  stateInput =
    RULE_BITS(
	      itc->pinStates[PIN_IRQLK],
	      itc->pinStates[PIN_IGRLK],
	      itc->isFred,
	      activeTry,
	      activeFree,
              istimeout
	      );

  rulep = ruleSetDispatchTable[itc->state];
  while (1) {
    if ((stateInput & rulep->mask) == rulep->bits) {
      nextState = rulep->newstate;

      if (entryFuncsForState[nextState]) /* Have a custom state entry function? */
        /* We do. Let it maybe update our destination */
        nextState = (*entryFuncsForState[nextState])(itc,stateInput); 

      break;
    }
    if (rulep->endmarker) break;
    ++rulep;
  }

  setState(itc,nextState);
}

void refreshInputs(ITCInfo* itc)
{
  unsigned irq = gpio_get_value(itc->pins[PIN_IRQLK].gpio);
  unsigned igr = gpio_get_value(itc->pins[PIN_IGRLK].gpio);
  BUG_ON(!itc);
  if (irq != itc->pinStates[PIN_IRQLK] ||
      igr != itc->pinStates[PIN_IGRLK]) {

    ADD_LOCK_EVENT_IRQ(makeSpecLockEvent(LET_SPEC_RFIC));
    printk(KERN_INFO "ITC %s i%d%d -> i%d%d\n",
           itcDirName(itc->direction),
           itc->pinStates[PIN_IRQLK],
           itc->pinStates[PIN_IGRLK],
           irq,
           igr
           );

    itc->pinStates[PIN_IRQLK] = irq;
    itc->pinStates[PIN_IGRLK] = igr;
  }
}

void updateStates(ITCIterator * itr, bool istimeout) {
  for (itcIteratorStart(itr); itcIteratorHasNext(itr);) {
    ITCDir idx = itcIteratorGetNext(itr);
    ITCInfo * itc = &S.itcInfo[idx];
    refreshInputs(itc);
    updateState(itc,istimeout);
  }
}

////CUSTOM STATE ENTRY FUNCTIONS
ITCState entryFunction_sWAIT(ITCInfo * itc,unsigned stateInput) {
  BUG_ON(!itc);
  /*
  printk(KERN_INFO "ITC %s i%d%d from %s efWAIT %08x, to %u, tol %u\n",
         itcDirName(itc->direction),
         itc->pinStates[PIN_IRQLK],
         itc->pinStates[PIN_IGRLK],
         getStateName(itc->state),
         stateInput,
         itc->magicWaitTimeouts,
         itc->magicWaitTimeoutLimit
         );
  */
  
  /* If we're timing-out in sWAIT, check magic counters */
  if (itc->state == sWAIT && (stateInput & BINP_TIMEOUT)) {
    /* If we've exhausted our patience.. */
    if (++itc->magicWaitTimeouts > itc->magicWaitTimeoutLimit) {
      /* ..be twice as patient next time, up to a limit..*/
      if (itc->magicWaitTimeoutLimit < (1<<10))
        itc->magicWaitTimeoutLimit <<= 1;
      /* ..and try failing instead of waiting.. */
      itc->magicWaitTimeouts = 0;
      return sFAILED;
    }
  }
  return sWAIT;
}

ITCState entryFunction_sRACE(ITCInfo * itc,unsigned stateInput) {
  BUG_ON(!itc);
  
  /* If lucky or time-out, go to idle */
  if (prandom_u32_max(4) == 0 || (stateInput & BINP_TIMEOUT)) {
    return sIDLE;
  }
  return sRACE;
}


ITCState entryFunction_sFAILED(ITCInfo * itc,unsigned stateInput) {
  BUG_ON(!itc);
  /* Getting to sFAILED from anywhere _but_ sWAIT seems a pathetic
     reason to have hope, but let's believe in love after love..*/
  if (itc->state != sWAIT) {
    itc->magicWaitTimeouts = 0;
    itc->magicWaitTimeoutLimit = 1;
  }
  return sFAILED;
}

static int itcThreadRunner(void *arg) {
  const int jiffyTimeout = HZ/10;

  ITCIterator idxItr;
  itcIteratorInitialize(&idxItr,5000); // init with rare shuffling

  printk(KERN_INFO "itcThreadRunner: Started\n");
  set_current_state(TASK_RUNNING);
  while(!kthread_should_stop()) {    // Returns true when kthread_stop() is called

    if (S.userRequestActive && time_before(S.userRequestTime + jiffyTimeout/10, jiffies)) {
      ADD_LOCK_EVENT_IRQ(makeSpecLockEvent(LET_SPEC_URTO)); /*timeout*/
#ifdef REPORT_LOCK_STATE_CHANGES
      printk(KERN_INFO "itcThreadRunner: Clearing userRequestActive\n");
#endif
      printk(KERN_INFO "ITR CLR USREQ kfifo_len=(%d)\n",kfifo_len(&S.mLockEventState.mEvents));
      printk(KERN_INFO "ITR CLR USREQ kfifo_avail=(%d)\n",kfifo_avail(&S.mLockEventState.mEvents));
      printk(KERN_INFO "ITR CLR USREQ mStartTime=(%lld)\n",S.mLockEventState.mStartTime);
      printk(KERN_INFO "ITR CLR USREQ mShiftDistance=(%d)\n",S.mLockEventState.mShiftDistance);
      userRequestDone(-ETIME);
   }

    {
      unsigned long flags;
      bool timeout = time_before(S.moduleLastActive + jiffyTimeout, jiffies);
      spin_lock_irqsave(&S.mdLock, flags);         // Grab mdLock
      updateStates(&idxItr,timeout);               // CRITICAL SECTION: mdLock
      if (timeout) S.moduleLastActive = jiffies;   // CRITICAL SECTION: mdLock
      spin_unlock_irqrestore(&S.mdLock, flags);    // Free mdLock
    }
    
#if 0
    if (time_before(S.moduleLastActive + jiffyTimeout, jiffies)) {
      /* NOPE WAY TOO MANY OF THESE      addLockEventIRQ(makeSpecLockEvent(LET_SPEC_ACTO)); internal timeout*/
      updateStates(&idxItr,true);
      S.moduleLastActive = jiffies;
    }
#endif

    make_reports();
    set_current_state(TASK_INTERRUPTIBLE);
    schedule_timeout(jiffyTimeout/2);   /* in TASK_RUNNING again upon return */
    //msleep(30);
  }
  printk(KERN_INFO "itcThreadRunner: Stopping by request\n");
  return 0;
}

/******************************/

///fops for /dev/itc/locks
static int     dev_open(struct inode *, struct file *);
static int     dev_release(struct inode *, struct file *);
static ssize_t dev_read(struct file *, char *, size_t, loff_t *);
static ssize_t dev_write(struct file *, const char *, size_t, loff_t *);

///fops for /dev/itc/lockevents
static int     lev_open(struct inode *, struct file *);
static int     lev_release(struct inode *, struct file *);
static ssize_t lev_read(struct file *, char *, size_t, loff_t *);
static ssize_t lev_write(struct file *, const char *, size_t, loff_t *);

static const struct file_operations itc_fops[MINOR_DEVICES] =
{
  {
    .owner = THIS_MODULE,
    .open = dev_open,
    .read = dev_read,
    .write = dev_write,
    .release = dev_release,
  },
  {
    .owner = THIS_MODULE,
    .open = lev_open,
    .read = lev_read,
    .write = lev_write,
    .release = lev_release,
  },
  
};

///// BEGIN CALLBACKS FOR /dev/itc/locks
static int dev_open(struct inode *inodep, struct file *filep) {
   S.numberOpens++;
   printk(KERN_INFO "ITC: " DEVICE_NAME0 " open #%d, flags=0%o, NB=%o/%o\n",
          S.numberOpens,
          filep->f_flags,
          filep->f_flags&O_NONBLOCK,
          O_NONBLOCK);
   return 0;
}

static ssize_t dev_read(struct file *filep, char *buffer, size_t len, loff_t *offset){
  enum { MAX_BUF = 256 };
  int error;
  bool waitForIt = !(filep->f_flags & O_NONBLOCK);

  ADD_LOCK_EVENT_IRQ(makeSpecLockEvent(waitForIt ? LET_SPEC_RBKU : LET_SPEC_RNBU));

  if (len > STATE_COUNT) len = STATE_COUNT;

  // Get the mutex (returns 0 unless interrupted)
  if ((error = mutex_lock_interruptible(&S.itc_mutex))) return error;

  error = copy_to_user(buffer, dirsInState, len); // ITC_MUTEX HELD

  mutex_unlock(&S.itc_mutex);
  if (len > 1) {
    addEventCurrentLockState(sTAKEN);
    if (len > 2) {
      addEventCurrentLockState(sGIVEN);
    }
  }

  ADD_LOCK_EVENT_IRQ(makeSpecLockEvent(error < 0 ? LET_SPEC_RRTE : LET_SPEC_RRTS));  /*returning to user*/

  if (error < 0)
    return error;

  return len;
}

static ssize_t dev_write(struct file *filep, const char *buffer, size_t len, loff_t *offset){

  u8 lockCmd;
  ssize_t ret;
  u32 bytesHandled;
  bool waitForIt = !(filep->f_flags & O_NONBLOCK);
  /*  printk(KERN_INFO "WRITE(len=%d,wait=%d)\n",len, waitForIt); */

  if (!waitForIt && len > 1)  /* Non-blocking can only write one byte */
    return -EPERM;

  ADD_LOCK_EVENT_IRQ(makeSpecLockEvent(waitForIt ? LET_SPEC_WBKU : LET_SPEC_WNBU));

  /* This loop written expecting len to most often be 1 */
  for (bytesHandled = 0; bytesHandled < len; ++bytesHandled) {
    ret = copy_from_user(&lockCmd, &buffer[bytesHandled], 1);
    if (ret != 0) {
      printk(KERN_INFO "Itc: copy_from_user failed\n");
      return -EFAULT;
    }

    // Get the mutex (returns 0 unless interrupted)
    if((ret = mutex_lock_interruptible(&S.itc_mutex))) return ret;

    ret = itcInterpretCommandByte(lockCmd, waitForIt);   // ITC_MUTEX HELD

    mutex_unlock(&S.itc_mutex);

    if (ret < 0) {            // If interpretcommandbyte saw a problem
      if (bytesHandled == 0)  { // If no bytes yet written
        ADD_LOCK_EVENT_IRQ(makeSpecLockEvent(LET_SPEC_WRTE));  /* that's an error */
        return ret;           // ..and you get the error code
      }
      break;                  // Otherwise you get a partial write
    } else if (S.userRequestStatus < 0) { // If later negotiation failed
      ADD_LOCK_EVENT_IRQ(makeSpecLockEvent(LET_SPEC_WRTE));  /* that's an error too */
      return S.userRequestStatus;       // There's your answer
    }
  }

  ADD_LOCK_EVENT_IRQ(makeSpecLockEvent(bytesHandled < len ? LET_SPEC_WRTP : LET_SPEC_WRTS));  /*returning to user*/
  return bytesHandled;
}

static int dev_release(struct inode *inodep, struct file *filep){
   mutex_unlock(&S.itc_mutex);                      // release the mutex (i.e., lock goes up)
   printk(KERN_INFO "ITC: " DEVICE_NAME0 " successfully closed\n");
   return 0;
}
///// END CALLBACKS FOR /dev/itc/locks

///// BEGIN CALLBACKS FOR /dev/itc/lockevents
static int lev_open(struct inode *inodep, struct file *filep)
{
  int ret = -EBUSY;
  ITCCharDeviceState * cdevstate = (ITCCharDeviceState *) inodep->i_cdev;

  if (!cdevstate->mDeviceOpenedFlag) {
    cdevstate->mDeviceOpenedFlag = true;
    filep->private_data = cdevstate;
    ret = 0;
  }

  if (ret)
    dev_err(cdevstate->mLinuxDev, "Device already open\n");

  return ret;
}

static ssize_t lev_read(struct file *filep, char *buffer, size_t len, loff_t *offset)
{
  int ret;
  ITCLockEventState * lec = &S.mLockEventState;
  u32 copied;

  len = len/sizeof(ITCLockEvent)*sizeof(ITCLockEvent); // Round off

  // Get read lock to read the event kfifo
  while ( (ret = mutex_lock_interruptible(&lec->mLockEventReadMutex)) ) {
    if ((filep->f_flags & O_NONBLOCK) || (ret != -EINTR)) return ret;
  }

  ret = kfifo_to_user(&lec->mEvents, buffer, len, &copied);

  mutex_unlock(&lec->mLockEventReadMutex);
  return ret ? ret : copied;
}

static ssize_t lev_write(struct file *filep, const char *buffer, size_t len, loff_t *offset)
{
  s32 ret;
  u8 levCmd;

  if (len != 1)  /* Only allowed to write one byte */
    return -EPERM;

  ret = copy_from_user(&levCmd, buffer, 1);
  if (ret != 0) {
    printk(KERN_INFO "Itc: copy_from_user failed\n");
    return -EFAULT;
  }

  if (levCmd != 0)       /*we only support 0->RESET at the moment*/
    return -EINVAL;

  // Flush the event kfifo and set up for trace
  while ( (ret = startLockEventTrace(&S.mLockEventState)) ) {
    if ((filep->f_flags & O_NONBLOCK) || (ret != -EINTR))
      break;
  }

  return ret ? ret : len;
}

static int lev_release(struct inode *inodep, struct file *filep){
  ITCCharDeviceState * cdevstate = (ITCCharDeviceState *) inodep->i_cdev;

  if (cdevstate->mDeviceOpenedFlag) {
    cdevstate->mDeviceOpenedFlag = false;
    printk(KERN_INFO "ITC: " DEVICE_NAME1 " successfully closed\n");
  } else {
    printk(KERN_INFO "ITC: " DEVICE_NAME1 " lev_release when not open??\n");
  }
  return 0;
}
///// END CALLBACKS FOR /dev/itc/lockevents


static void initModuleState(ITCModuleState* s) {
  spin_lock_init(&s->mdLock);
  init_waitqueue_head(&s->userWaitQ);
  mutex_init(&s->itc_mutex);
  initLockEventState(&s->mLockEventState);
}

static void destroyModuleState(ITCModuleState* s) {
   mutex_destroy(&s->itc_mutex); // destroy the mutex
}
static ssize_t status_show(struct class *c,
			   struct class_attribute *attr,
			   char *buf)
{
  sprintf(buf,"%02x%02x%02x%02x\n"
          ,getSettlementValue(LOCK_UNREADY)
          ,getSettlementValue(LOCK_AVAILABLE)
          ,getSettlementValue(LOCK_UNSETTLED)
          ,getSettlementValue(LOCK_SETTLED)
          );
  return strlen(buf);
}
CLASS_ATTR_RO(status);

static ssize_t trace_start_time_show(struct class *c,
				     struct class_attribute *attr,
				     char *buf)
{
  sprintf(buf,"%lld\n",S.mLockEventState.mStartTime);
  return strlen(buf);
}
CLASS_ATTR_RO(trace_start_time);

static ssize_t shift_show(struct class *c,
			  struct class_attribute *attr,
			  char *buf)
{
  sprintf(buf,"%d\n",S.mLockEventState.mShiftDistance);
  return strlen(buf);
}

static ssize_t shift_store(struct class *c,
			   struct class_attribute *attr,
			   const char *buf,
			   size_t count)
{
  u32 shift;
  if (sscanf(buf,"%u",&shift) == 1 && shift < 64) {
    printk(KERN_INFO "store shift %u\n",shift);
    S.mLockEventState.mShiftDistance = shift;
    return count;
  }
  return -EINVAL;
}
CLASS_ATTR_RW(shift);

static ssize_t statistics_show(struct class *c,
			       struct class_attribute *attr,
			       char *buf)
{
  int dir, state, len = 0;
  len += sprintf(&buf[len],"DIR");
  for (state = 0; state < STATE_COUNT; ++state)
    len += sprintf(&buf[len]," %s",stateNames[state]);
  len += sprintf(&buf[len],"\n");
  
  for (dir = 0; dir < DIR_COUNT; ++dir) {
    ITCInfo * iti = &S.itcInfo[dir];
    len += sprintf(&buf[len],"%s ",itcDirName(dir));

    for (state = 0; state < STATE_COUNT; ++state) 
      len += sprintf(&buf[len]," %lu",iti->enteredCount[state]);
    len += sprintf(&buf[len],"\n");
  }

  return strlen(buf);
}

static ssize_t statistics_store(struct class *c,
				struct class_attribute *attr,
				const char *buf,
				size_t count)
{
  u32 cleardirs, dir, state;
  if (sscanf(buf,"%x",&cleardirs) == 1) {
    printk(KERN_INFO "store statistics %u\n",cleardirs);
    for (dir = 0; dir < DIR_COUNT; ++dir) {
      if (cleardirs & (1<<dir)) {
        ITCInfo * iti = &S.itcInfo[dir];
        for (state = 0; state < STATE_COUNT; ++state) 
          iti->enteredCount[state] = 0;
      }
    }

    return count;
  }
  return -EINVAL;
}
CLASS_ATTR_RW(statistics);

////////////////BEGIN CLASS ATTRIBUTE STUFF
#if 0
static struct class_attribute itc_class_attrs[] = {
  __ATTR(status, 0444, itc_class_read_status, NULL), /*just picking one to have something*/
  __ATTR(trace_start_time, 0444, itc_class_read_trace_start_time, NULL), 
  __ATTR(shift, 0644, itc_class_read_shift, itc_class_store_shift),
  __ATTR(statistics, 0644, itc_class_read_statistics, itc_class_store_statistics),
#if 0
  __ATTR(poke, 0200, NULL, itc_pkt_class_store_poke),
  __ATTR(trace, 0644, itc_pkt_class_read_trace, itc_pkt_class_store_trace),
  __ATTR(statistics, 0444, itc_pkt_class_read_statistics, NULL),
  __ATTR(pru_bufs, 0444, itc_pkt_class_read_pru_bufs, NULL),
  __ATTR(pkt_bufs, 0444, itc_pkt_class_read_pkt_bufs, NULL),
#endif
  __ATTR_NULL,
};
#else
static struct attribute * class_itc_attrs[] = {
  &class_attr_status.attr,
  &class_attr_trace_start_time.attr,
  &class_attr_shift.attr,
  &class_attr_statistics.attr,
  NULL,
};
ATTRIBUTE_GROUPS(class_itc);
#endif

static struct attribute *itc_attrs[] = {
  NULL,
};

static struct bin_attribute * itc_bin_attrs[] = {
  NULL,
};

static const struct attribute_group itc_group = {
  .attrs = itc_attrs,
  .bin_attrs = itc_bin_attrs,
};

static const struct attribute_group * itc_groups[] = {
  &itc_group,
  NULL,
};

static struct class itc_class_instance = {
  .name = "itc",
  .owner = THIS_MODULE,
  .class_groups = class_itc_groups,
  .dev_groups = itc_groups,
};

////////////////END CLASS ATTRIBUTE STUFF

static int makeITCCharDeviceState(ITCCharDeviceState * cdevstate,
                                  int minor_obtained)
{
  enum { BUFSZ = 32 };
  char devname[BUFSZ];
  int ret = 0;

  BUG_ON(!cdevstate);

  switch (minor_obtained) {
  case 0: snprintf(devname,BUFSZ,DEVICE_NAME0); break;
  case 1: snprintf(devname,BUFSZ,DEVICE_NAME1); break;
  default:
    {
      ret = -EINVAL;
      goto fail_minor;
    }
  }

  printk(KERN_INFO "LERGIN: makeITCCharDeviceState(%d) for %s\n",
         minor_obtained, devname);

  strncpy(cdevstate->mName,devname,DBG_NAME_MAX_LENGTH);
  cdevstate->mDevt = MKDEV(MAJOR(S.majorNumber), minor_obtained);

  printk(KERN_INFO "LINITTING /dev/%s with minor_obtained=%d (cdevs=%p)\n",
         devname, minor_obtained, cdevstate);

  cdev_init(&cdevstate->mLinuxCdev, &itc_fops[minor_obtained]);
  cdevstate->mLinuxCdev.owner = THIS_MODULE;
  ret = cdev_add(&cdevstate->mLinuxCdev, cdevstate->mDevt,1);

  if (ret) {
    printk(KERN_ALERT "Unable to init cdev\n");
    goto fail_cdev_init;
  }

  printk(KERN_INFO "LRZOG Back from cdev_init+cdev_add\n");

  printk(KERN_INFO "LGRZO going to device_create(%p,devt=(%d:%d),NULL,%s)\n",
         &itc_class_instance,
         MAJOR(cdevstate->mDevt), MINOR(cdevstate->mDevt),
         devname);

  cdevstate->mLinuxDev = device_create(&itc_class_instance,
                                       NULL,
                                       cdevstate->mDevt,
                                       NULL,
                                       devname);

  printk(KERN_INFO "LGOZR Back from device_create dev=%p\n", cdevstate->mLinuxDev);

  if (IS_ERR(cdevstate->mLinuxDev)) {
    printk(KERN_ALERT "Failed to create device file entries\n");
    ret = PTR_ERR(cdevstate->mLinuxDev);
    goto fail_device_create;
  }

  printk(KERN_INFO "L ITCCharDeviceState early init done on /dev/%s",devname);

  return 0;  /*success*/

 fail_device_create:
  cdev_del(&cdevstate->mLinuxCdev);

 fail_cdev_init:

 fail_minor:
  return ret;
}

static void unmakeITCCharDeviceState(ITCCharDeviceState * cdevstate) {
  device_destroy(&itc_class_instance, cdevstate->mDevt);
  cdev_del(&cdevstate->mLinuxCdev);
}

static int __init itc_init(void)
{
  int ret = 0;
  printk(KERN_INFO "ITC: INIT START\n");

  //// 0: non-static inits of module global state 
  initModuleState(&S); 

  //// 1: set up pins
  itcInitGPIOs();

  printk(KERN_INFO "ITC: CLASS INITS\n");

  //// 2: class registrations
  ret = class_register(&itc_class_instance);
  if (ret) {
    pr_err("Failed to register class\n");
    goto fail_class_register;
  }
  S.itcClass = &itc_class_instance; /* Save pointer */

  //// 3: device number allocations
  ret = alloc_chrdev_region(&S.majorNumber, 0, MINOR_DEVICES, "itc");
  if (ret) {
    pr_err("Failed to allocate chrdev region\n");
    goto fail_alloc_chrdev_region;
  }
  printk(KERN_INFO "ITC: Allocated major number %d + %d minors\n", MAJOR(S.majorNumber), MINOR_DEVICES);

  //// 4: Device creation
  for (S.minorsBuilt = 0; S.minorsBuilt < MINOR_DEVICES; ++S.minorsBuilt) {
    ret = makeITCCharDeviceState(&S.mDeviceState[S.minorsBuilt], S.minorsBuilt);

    if (ret){          // Clean up if there is an error
      printk(KERN_ALERT "ITC: Failed to create the device\n");
      goto fail_register_driver;
    }
  }

  printk(KERN_INFO "ITC: Device class created correctly\n"); // Made it! device was initialized

  //// 5: Thread start
  S.itcThreadRunnerTask = kthread_run(itcThreadRunner, NULL, "ITC_LockTimr");  
  if(IS_ERR(S.itcThreadRunnerTask)){                                     
    printk(KERN_ALERT "ITC: Thread creation failed\n");
    ret = PTR_ERR(S.itcThreadRunnerTask);
    goto fail_thread_create;
  }

  //// 6: Enable interrupts on ITC pins
  itcInitGPIOInterrupts();

  //// 7: Setup done
  printk(KERN_INFO "ITC init done\n");
  return 0;

 fail_thread_create:
  device_destroy(S.itcClass, MKDEV(S.majorNumber, 0));
  /*FALL THROUGH */

 fail_register_driver:
  unregister_chrdev_region(S.majorNumber, MINOR_DEVICES);
  /*FALL THROUGH */

 fail_alloc_chrdev_region:
  class_unregister(&itc_class_instance);
  /*FALL THROUGH */

 fail_class_register:
   return ret;
}

/** @brief The LKM cleanup function
 *  Similar to the initialization function, it is static. The __exit macro notifies that if this
 *  code is used for a built-in driver (not a LKM) that this function is not required.
 */
static void __exit itc_exit(void){
  //// UNDO 7: Setup done
  printk(KERN_INFO "ITC exit start\n");

  //// UNDO 6: Free ITC GPIO interrupts
  itcExitGPIOInterrupts();

  //// UNDO 5: Thread start
  kthread_stop(S.itcThreadRunnerTask);               // Kill the timing thread

  //// UNDO 4: Device creation
  while (S.minorsBuilt > 0) {
    unmakeITCCharDeviceState(&S.mDeviceState[--S.minorsBuilt]);
  }

  //// UNDO 3: device number allocations
  unregister_chrdev_region(S.majorNumber, MINOR_DEVICES);

  //// UNDO 2: class registrations
  class_unregister(&itc_class_instance);

  //// UNDO 1: unconfigure pins
  itcExitGPIOs();

  //// UNDO 0: late (non-static) inits of module global state 
  destroyModuleState(&S);

  printk(KERN_INFO "ITC: EXIT DONE\n");
}

module_init(itc_init);
module_exit(itc_exit);

MODULE_LICENSE("GPL");            ///< All MFM code is LGPL or GPL licensed
MODULE_AUTHOR("Dave Ackley");     ///< Email: ackley@ackleyshack.com
MODULE_DESCRIPTION("T2 intertile lock manager");  ///< modinfo description
MODULE_VERSION("2.0");            ///< 2.0 201909211534 first cut at sGIVEN-uFREE->sRELEASE
//MODULE_VERSION("1.1");            ///< 1.1 201907260159 statistics, extended write status
//MODULE_VERSION("1.0");            ///< 1.0 201907250852 sRELEASE allowing fast blocking I/O
//MODULE_VERSION("0.9");            ///< 0.9 201907250406 online lock settlement info
//MODULE_VERSION("0.8");            ///< 0.8 201907241208 try stochastic sRACE->sIDLE
//MODULE_VERSION("0.7");            ///< 0.7 201907240850 try unconditional sRACE->sIDLE
//MODULE_VERSION("0.6");            ///< 0.6 201907240216 tracing lock events
//MODULE_VERSION("0.5");            ///< 0.5 201907190208 rewrite init/exit sequence
//MODULE_VERSION("0.4");            ///< 0.4 201907180304 rewrite as single file
//MODULE_VERSION("0.3");            ///< 0.3 201907152109 rework for a little speed

