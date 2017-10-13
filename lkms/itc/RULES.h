/* THIS IS THE MASTER FILE CONTAINING ALL STATE TRANSITION INFO */
/* NO #define/#ifndef macro guard here!  File is included multiple times! */

RS(sRESET,o11, /** Initial and ground state, entered on any error */
   R_ITC(G,i11,sSYNC01), /* ginger moves first from sRESET */
   R_ITC(F,i11,sRESET),  /* fred waits for ginger in sRESET */
   R_ITC(F,i01,sSYNC01), /* fred reacts to ginger's move */
   R_END(sFAILED))       /* else punt */

RS(sSYNC01,o11, /** Out of reset, looking for i01 */
   R_ITC(G,i11,sSYNC01), /* ginger waits while fred's in reset */
   R_ITC(F,i01,sSYNC01), /* fred waits for ginger to leave SYNC01 */
   R_ITC(G,i01,sIDLE),   /* ginger moves first from SYNC01 */
   R_ITC(F,i00,sIDLE),   /* fred reacts to ginger's move */
   R_END(sFAILED))       /* else punt */

RS(sIDLE,o00, /** In sync, waiting for a lock grab */
   R_INP(i01,sIDLE),     /* ignore leftover grants (from reset or uFREE) */
   R_INP(i00,sIDLE),     /* we're both idle */
   R_INP(i10,sGIVE),     /* they took the lock */
   R_USR(uTRY,sTAKE),    /* we're going for the lock */
   R_END(sFAILED))       /* they must have reset, die with them */

RS(sGIVE,o01,  /** They've got the lock */
   R_INP(i10,sGIVE),	 /* they're still holding the lock */
   R_INP(i00,sIDLE),	 /* they freed the lock */
   R_END(sFAILED))       /* else punt */

RS(sTAKE,o10,  /** We're going for lock */
   R_INP(i00,sTAKE),	 /* we're still hoping for the lock */
   R_INP(i01,sTAKEN),	 /* we got the lock */
   R_INP(i10,sRACE),     /* we both reached for the gun */
   R_END(sFAILED))       /* else punt */

RS(sRACE,o11,  /** A race has been detected */
   R_END(sFAILED))       /* for now just punt */

RS(sTAKEN,o10,  /** We've got the lock */
   R_USR(uFREE,sIDLE),   /* we freed the lock */
   R_INP(i01,sTAKEN),    /* we still hold the lock */
   R_END(sFAILED))       /* uh-oh the lock broke under us */

RS(sFAILED,o11, /** Something went wrong, reset required  */
   R_INP(i11,sRESET),    /* i11, you bet: It's the only way to get */
   R_END(sFAILED))       /* off of FAILED onto RESET (burma shave)*/
