#ifndef ITC_H
#define ITC_H

#ifndef NO_LINUX_HEADERS
#include <linux/init.h>            /* Macros used to mark up functions e.g. __init __exit */
#include <linux/cdev.h>
#include <linux/module.h>          /* Core header for loading LKMs into the kernel */
#include <linux/device.h>          /* Header to support the kernel Driver Model */
#include <linux/kernel.h>          /* Contains types, macros, functions for the kernel */
#include <linux/fs.h>              /* Header for the Linux file system support */
#include <asm/uaccess.h>           /* Required for the copy to user function */
#include <linux/uaccess.h>         /* Now required for the copy to user function */
#include <linux/mutex.h>	   /* Required for the mutex functionality */
#include <linux/spinlock.h>        /* For spinlock_t */
#include <linux/kthread.h>         /* For thread functions */
#include <linux/random.h>          /* for prandom_u32_max() */
#include <linux/delay.h>           /* for msleep() */
#include <linux/jiffies.h>         /* for time_before(), time_after() */
#include <linux/interrupt.h>	   /* for interrupt functions.. */
#include <linux/gpio.h>		   /* for gpio functions.. */
#include <linux/timekeeping.h>     /* for ktime_get_raw().. */
#include <linux/kfifo.h>           /* for kfifo.. */
#endif /* NO_LINUX_HEADERS */

#include "dirdatamacro.h"          /* Get itc pin info and basic enums */ 
#include "gdrodrivermacro.h"       /* Get GDRO mappings */ 
#include "itclockevent.h"          /* Get lock event struct */
#include "itc_iterator.h"          /* Get randomized itc iteratros */
#include "ruleset.h"               /* Get rule macros and constants, LockSettlements */

typedef unsigned long JiffyUnit;
typedef unsigned long ITCCounter;
typedef unsigned char ITCState;
typedef unsigned int BitValue;
typedef int IRQNumber;

typedef unsigned char Dir6;
typedef unsigned char ITCPin;
typedef unsigned char GDRONumber;

////////GDRO INFO STRUCT
typedef struct gdrodriverinfo {
  const char * driverName;
  const bool isJerk;
  const Dir6 inITC;
  const ITCPin inPin;
  const Dir6 outITC;
  const ITCPin outPin;
} GDRODriverInfo;

typedef struct gdrodriverstate {
  const GDRONumber gdroNumber;
  unsigned char skipCount;
  bool ringing;
  bool output;
  JiffyUnit lastEdge;
} GDRODriverState;

/////////TRACING SUPPORT

#define LOCK_EVENT_KFIFO_SIZE (1<<13)   /* Lock events are four bytes.  Guarantee space for 2K (4*2048 == 8,192 == 2**13) */
typedef STRUCT_KFIFO(ITCLockEvent, LOCK_EVENT_KFIFO_SIZE) ITCLockEventFIFO;

typedef struct itclockeventstate {
  ITCLockEventFIFO mEvents;
  u64 mStartTime;
  u8 mShiftDistance;
  struct mutex mLockEventReadMutex;	///< For read ops on kfifo
} ITCLockEventState;

typedef struct itcInfo {
  const struct gpio * const pins;
  const ITCDir direction;
  const bool isFred;
  BitValue pinStates[PIN_COUNT];
  ITCState state;
  ITCCounter enteredCount[STATE_COUNT];
  ITCCounter interruptsTaken;
  ITCCounter edgesMissed[2]; // PIN_IRQLK or PIN_IGRLK
  JiffyUnit lastActive;
  JiffyUnit lastReported;
  unsigned magicWaitTimeouts;
  unsigned magicWaitTimeoutLimit;
} ITCInfo;

#define DBG_NAME_MAX_LENGTH 32

typedef struct {             /* General char device state */
  struct cdev mLinuxCdev;    /* Linux character device state */
  struct device *mLinuxDev;  /* Ptr to linux device struct */
  dev_t mDevt;               /* Major:minor assigned to this device */
  bool mDeviceOpenedFlag;    /* true between .open and .close calls */
  char mName[DBG_NAME_MAX_LENGTH];   /* debug name of device */
} ITCCharDeviceState;

#define MINOR_DEVICES 2      /* /dev/itc/locks /dev/itc/lockevents */

enum {
  LOCKSET_CMD_VALUE_TRY =    0x0<<6,
  LOCKSET_CMD_VALUE_FREE =   0x1<<6,
  LOCKSET_CMD_VALUE_DROP =   0x2<<6,
  LOCKSET_CMD_VALUE_ENABLE = 0x3<<6,
  LOCKSET_CMD_MASK = 0x3<<6
};

typedef struct moduleState {
  ITCIterator userContextIterator;
  JiffyUnit moduleLastActive;
  ITCInfo itcInfo[DIR6_COUNT];
  JiffyUnit userRequestTime;
#if 0
  LockSettlements lockSettlements;
#endif
  u8 userLockset;               ///< 2 bit command + 6 bit lock mask
  bool userRequestActive;
  s32 userRequestStatus;
  dev_t majorNumber;            ///< Our assigned device number
  int    numberOpens;           ///< Stats: Number of times the device is opened
  struct class*  itcClass;      ///< The device-driver class struct pointer
  wait_queue_head_t userWaitQ;  ///< For user context sleeping during lock negotiations 
  spinlock_t mdLock;            ///< Spin lock for modifying this struct
  struct mutex itc_mutex;	///< For protecting access to lock info
  struct task_struct * itcThreadRunnerTask; /// Thread task pointer
  int minorsBuilt;              ///< Number of mDeviceStates open
  ITCCharDeviceState mDeviceState[MINOR_DEVICES]; ///< State for /dev/itc/locks

  ITCLockEventState mLockEventState; ///< State for /sys/class/itc/trace

} ITCModuleState;


#endif /* ITC_H */
