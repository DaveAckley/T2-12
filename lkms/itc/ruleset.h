#ifndef RULESET_H
#define RULESET_H

typedef struct _rule {
  u8 bits;
  u8 mask;
  u8 newstate;
  u8 endmarker;
} Rule;

typedef enum settlementstate {
  LOCK_UNREADY,    /* for sRESET, sSYNC01, sFAILED, sWAIT */
  LOCK_AVAILABLE,  /* for sIDLE */
  LOCK_UNSETTLED,  /* for sTAKE, sRELEASE, sRACE */
  LOCK_SETTLED,    /* for sTAKEN, sGIVEN */
  LOCK_RSRVD1
} SettlementState;

#define RULE_BITS(irqlk,igrlk,isfred,try,free,timeout) (	\
  ((irqlk)<<0) | \
  ((igrlk)<<1) | \
  ((isfred)<<2) | \
  ((try)<<3) | \
  ((free)<<4) | \
  ((timeout)<<5))


enum RuleInputBits {
  BINP_PIN_IRQLK = RULE_BITS(1,0,0,0,0,0),
  BINP_PIN_IGRLK = RULE_BITS(0,1,0,0,0,0),
  BINP_ITC_ISFRED= RULE_BITS(0,0,1,0,0,0),
  BINP_USR_TRY   = RULE_BITS(0,0,0,1,0,0),
  BINP_USR_FREE  = RULE_BITS(0,0,0,0,1,0),
  BINP_TIMEOUT   = RULE_BITS(0,0,0,0,0,1),
};

enum RuleOutputBits {
  BOUT_PIN_ORQLK = 0x02, // Left bit in oXX
  BOUT_PIN_OGRLK = 0x01, // Right bit in oXX
};

enum ValuesAndMasks {
  INPUT_VALUE_i00 = 0,
  INPUT_VALUE_i01 = BINP_PIN_IGRLK,
  INPUT_VALUE_i10 = BINP_PIN_IRQLK,
  INPUT_VALUE_i11 = BINP_PIN_IRQLK|BINP_PIN_IGRLK,
  INPUT_VALUE_i_0 = 0,
  INPUT_VALUE_i_1 = BINP_PIN_IGRLK,
  INPUT_VALUE_i0_ = 0,
  INPUT_VALUE_i1_ = BINP_PIN_IRQLK,
  INPUT_VALUE_i__ = 0,
  INPUT_MASKV_i00 = BINP_PIN_IRQLK|BINP_PIN_IGRLK,
  INPUT_MASKV_i01 = BINP_PIN_IRQLK|BINP_PIN_IGRLK,
  INPUT_MASKV_i10 = BINP_PIN_IRQLK|BINP_PIN_IGRLK,
  INPUT_MASKV_i11 = BINP_PIN_IRQLK|BINP_PIN_IGRLK,
  INPUT_MASKV_i_0 = BINP_PIN_IGRLK,
  INPUT_MASKV_i_1 = BINP_PIN_IGRLK,
  INPUT_MASKV_i0_ = BINP_PIN_IRQLK,
  INPUT_MASKV_i1_ = BINP_PIN_IRQLK,
  INPUT_MASKV_i__ = 0,

  ITCSD_VALUE_cF = BINP_ITC_ISFRED,
  ITCSD_VALUE_cG = 0,
  ITCSD_VALUE_c_ = 0,
  ITCSD_MASKV_cF = BINP_ITC_ISFRED,
  ITCSD_MASKV_cG = BINP_ITC_ISFRED,
  ITCSD_MASKV_c_ = 0,

  USER_VALUE_u_ = 0,
  USER_MASKV_u_ = 0,
  USER_VALUE_uTRY = BINP_USR_TRY,
  USER_MASKV_uTRY = BINP_USR_TRY|BINP_USR_FREE,
  USER_VALUE_uFREE = BINP_USR_FREE,
  USER_MASKV_uFREE = BINP_USR_TRY|BINP_USR_FREE,

  TIMEOUT_VALUE_t_ = 0,
  TIMEOUT_VALUE_to = BINP_TIMEOUT,
  TIMEOUT_MASKV_t_ = 0,
  TIMEOUT_MASKV_to = BINP_TIMEOUT,

  OUTPUT_VALUE_o00 = 0,
  OUTPUT_VALUE_o01 = BOUT_PIN_OGRLK,
  OUTPUT_VALUE_o10 = BOUT_PIN_ORQLK,
  OUTPUT_VALUE_o11 = BOUT_PIN_ORQLK|BOUT_PIN_OGRLK,
};

/* Function pointer meaning 'no entry function' */
#define entryFunction__ NULL

#define R_INP(input,newst)       R_ALL(_,u_,input,t_,newst,0)
#define R_USR(user,newst)        R_ALL(_,user,i__,t_,newst,0)
#define R_ITC(side,input,newst)  R_ALL(side,u_,input,t_,newst,0)
#define R_ITM(side,newst)        R_ALL(side,u_,i__,to,newst,0)

#define R_ALL(side,user,input,timeout,newst,endm)                       \
  { .bits = ((ITCSD_VALUE_c##side)|(USER_VALUE_##user)|(INPUT_VALUE_##input)|(TIMEOUT_VALUE_##timeout)), \
    .mask = ((ITCSD_MASKV_c##side)|(USER_MASKV_##user)|(INPUT_MASKV_##input)|(TIMEOUT_MASKV_##timeout)), \
    .newstate = (newst),						       \
    .endmarker = (endm)                                                        \
  }
#define R_END(newst) R_ALL(_,u_,i__,t_,newst,1)

#endif /* RULESET_H */
