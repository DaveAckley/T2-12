#ifndef ITCIMPL_H
#define ITCIMPL_H

#include <linux/init.h>           // Macros used to mark up functions e.g. __init __exit
#include <linux/module.h>         // Core header for loading LKMs into the kernel
#include <linux/device.h>         // Header to support the kernel Driver Model
#include <linux/kernel.h>         // Contains types, macros, functions for the kernel
#include <linux/fs.h>             // Header for the Linux file system support
#include <asm/uaccess.h>          // Required for the copy to user function
#include <linux/mutex.h>	  // Required for the mutex functionality
#include <linux/kthread.h>          /* For thread functions */

int itcThreadRunner(void *arg) ;
void itcImplInit(void) ;
void itcImplExit(void) ;
int itcGetCurrentLockInfo(u8 buffer[4], int len) ;

// itcTryForLockset
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
//  o 1 if we successfully took all requested locks and released any
//    others that we may have been holding

ssize_t itcTryForLockset(u8 lockset) ;

#endif /* ITCIMPL_H */
