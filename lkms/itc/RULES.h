#ifndef RULES_H
#define RULES_H
/* THIS IS THE MASTER FILE CONTAINING ALL STATE TRANSITION INFO */

/* DEFAULT RULESET GENERATORS */
#ifndef RSE
#define RSE(forState,output,settlement,...) RS(forState,forState,output,settlement,__VA_ARGS__)
#define undefRSEafter
#endif

#ifndef RSN
#define RSN(forState,output,settlement,...) RS(forState,_,output,settlement,__VA_ARGS__)
#define undefRSNafter
#endif

/////////////
/////BEGIN RULE SETS

#define ALLRULESMACRO() /*state numbers determined by this rule order*/ \
  RSN(sRESET,o11,LOCK_UNREADY, /** Initial and ground state, must be first */ \
      R_ITC(G,i11,sSYNC01), /* ginger moves first from sRESET */        \
      R_ITC(F,i11,sRESET),  /* fred waits for ginger in sRESET */       \
      R_ITC(F,i01,sSYNC01), /* fred reacts to ginger's move */          \
      R_END(sFAILED))       /* else punt */                             \
                                                                        \
  RSN(sTAKEN,o10,LOCK_SETTLED,  /** We've got the lock */               \
      R_USR(uFREE,sRELEASE),/* we want to free the lock */              \
      R_INP(i01,sTAKEN),    /* we still hold the lock */                \
      R_END(sFAILED))       /* uh-oh the lock broke under us */         \
                                                                        \
  RSN(sGIVEN,o01,LOCK_SETTLED,  /** They've got the lock */             \
      R_INP(i10,sGIVEN),    /* they're still holding the lock */        \
      R_INP(i00,sIDLE),	    /* they freed the lock */                   \
      R_END(sFAILED))       /* else punt */                             \
                                                                        \
  RSN(sIDLE,o00,LOCK_AVAILABLE, /** In sync, waiting for a lock grab */ \
      R_INP(i01,sIDLE),     /* ignore leftover grants (from reset or uFREE) */ \
      R_INP(i10,sGIVEN),    /* they took the lock */                    \
      R_USR(uTRY,sTAKE),    /* we're going for the lock */              \
      R_INP(i00,sIDLE),     /* we're both just idle */                  \
      R_END(sFAILED))       /* they must have reset, die with them */   \
                                                                        \
  RSN(sTAKE,o10,LOCK_UNSETTLED,  /** We're going for lock */            \
      R_ITM(_,sFAILED),     /* both sides fail if timeout waiting for lock */ \
      R_INP(i00,sTAKE),	    /* we're still hoping for the lock */       \
      R_INP(i01,sTAKEN),    /* we got the lock */                       \
      R_INP(i10,sRACE),     /* we both reached for the gun */           \
      R_END(sFAILED))       /* else punt */                             \
                                                                        \
  RSN(sRELEASE,o00,LOCK_UNSETTLED,  /** We're freeing the lock */       \
      R_ITM(_,sFAILED),     /* fail if timeout waiting for ack */       \
      R_INP(i01,sRELEASE),  /* waiting for them to ack */               \
      R_INP(i00,sIDLE),     /* we go idle when they agree */            \
      R_END(sFAILED))       /* uh-oh the lock broke under us */         \
                                                                        \
  RSN(sSYNC01,o01,LOCK_UNREADY, /** Out of reset, looking for i01 */    \
      R_ITM(G,sWAIT),       /* ginger goes to special state if timeout waiting for fred */ \
      R_ITC(G,i11,sSYNC01), /* ginger waits while fred's in reset */    \
      R_ITC(F,i01,sSYNC01), /* fred waits for ginger to leave SYNC01 */ \
      R_ITC(G,i01,sIDLE),   /* ginger moves first from SYNC01 */        \
      R_ITC(F,i00,sIDLE),   /* fred reacts to ginger's move */          \
      R_END(sFAILED))       /* else punt */                             \
                                                                        \
  RSE(sWAIT,o11,LOCK_UNREADY, /** Magic increasing timeout wait state, reset by entering sRESET */ \
      R_INP(i0_,sFAILED),   /* Go fail if any sign of life */           \
      R_INP(i_0,sFAILED),   /* Go fail if any sign of life */           \
      R_END(sWAIT))         /* Otherwise keep waiting (until magic kicks in) */ \
                                                                        \
  RSE(sRACE,o11,LOCK_UNSETTLED,  /** A race has been detected; do magic */ \
      R_END(sRACE))         /* go try again */                          \
                                                                        \
  RSE(sFAILED,o11,LOCK_UNREADY, /** Something went wrong, reset required  */ \
      R_INP(i11,sRESET),    /* i11, you bet: It's the only way to get */ \
      R_END(sFAILED))       /* off of FAILED onto RESET (burma shave)*/ \
                                                                        \

/////END RULE SETS
/////////////


/* CLEAN UP RULESET GENERATORS */
#ifdef undefRSEafter
#undef RSE
#undef undefRSEafter
#endif

#ifdef undefRSNafter
#undef RSN
#undef undefRSNafter
#endif

#endif /*RULES_H*/
