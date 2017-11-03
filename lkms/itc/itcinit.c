/**
 * @file   itcinit.c
 * @author Dave Ackley
 * @date   7 October 2017
 * @version 0.1
 *
 * @brief A character driver to support the intertile locking
 * semantics of the MFM T2 tile. (Aspirationally,) This module maps to
 * /dev/itc and /sys/class/itc
 *
 * @see http://robust.cs.unm.edu/ for a backgrounder on the project,
 * and who-knows-where for a specific description of the T2 intertile
 * locking semantics.
 */

#include "itcimpl.h"

#define  DEVICE_NAME "itc!locks"  ///< The device will appear at /dev/itc/locks/
#define  CLASS_NAME  "itccls"     ///< The device class -- this is a character device driver

MODULE_LICENSE("GPL");            ///< All MFM code is LGPL or GPL licensed
MODULE_AUTHOR("Dave Ackley");     ///< Email: ackley@ackleyshack.com
MODULE_DESCRIPTION("Access and control the T2 intertile connection system");  ///< modinfo description
MODULE_VERSION("0.2");            ///< 0.2 for initial char device code

static int    majorNumber;                  ///< Our assigned device number
static int    numberOpens = 0;              ///< Stats: Number of times the device is opened
static struct class*  itcClass  = NULL; ///< The device-driver class struct pointer
static struct device* itcDevice = NULL; ///< The device-driver device struct pointer

static struct task_struct *task;            /// The pointer to the thread task

static DEFINE_MUTEX(itc_mutex);	    ///< Macro to declare a new mutex

/// The prototype functions for the character driver -- must come before the struct definition
static int     dev_open(struct inode *, struct file *);
static int     dev_release(struct inode *, struct file *);
static ssize_t dev_read(struct file *, char *, size_t, loff_t *);
static ssize_t dev_write(struct file *, const char *, size_t, loff_t *);

/**
 * Devices are represented as file structure in the kernel. The file_operations structure from
 * /linux/fs.h lists the callback functions that you wish to associated with your file operations
 * using a C99 syntax structure. char devices usually implement open, read, write and release calls
 */
static struct file_operations fops =
{
   .owner = THIS_MODULE,
   .open = dev_open,
   .read = dev_read,
   .write = dev_write,
   .release = dev_release,
};

/** @brief The LKM initialization function
 *  The static keyword restricts the visibility of the function to within this C file. The __init
 *  macro means that for a built-in driver (not a LKM) the function is only used at initialization
 *  time and that it can be discarded and its memory freed up after that point.
 *  @return returns 0 if successful
 */
static int __init itc_init(void){
   printk(KERN_INFO "ITC: Initializing LKM\n");
   itcImplInit();

   // Try to dynamically allocate a major number for the device -- more difficult but worth it
   majorNumber = register_chrdev(0, DEVICE_NAME, &fops);
   if (majorNumber<0) {
      printk(KERN_ALERT "ITC: Failed to register a major number\n");
      return majorNumber;
   }
   printk(KERN_INFO "ITC: Registered correctly with major number %d\n", majorNumber);

   // Register the device class
   itcClass = class_create(THIS_MODULE, CLASS_NAME);
   if (IS_ERR(itcClass)){           // Check for error and clean up if there is
      unregister_chrdev(majorNumber, DEVICE_NAME);
      printk(KERN_ALERT "Failed to register device class\n");
      return PTR_ERR(itcClass);     // Correct way to return an error on a pointer
   }
   printk(KERN_INFO "ITC: Device class registered correctly\n");

   // Register the device driver
   itcDevice = device_create(itcClass, NULL, MKDEV(majorNumber, 0), NULL, DEVICE_NAME);
   if (IS_ERR(itcDevice)){          // Clean up if there is an error
      class_destroy(itcClass);      // Repeated code but the alternative is goto statements
      unregister_chrdev(majorNumber, DEVICE_NAME);
      printk(KERN_ALERT "ITC: Failed to create the device\n");
      return PTR_ERR(itcDevice);
   }
   printk(KERN_INFO "ITC: Device class created correctly\n"); // Made it! device was initialized
   mutex_init(&itc_mutex);          // Initialize the mutex dynamically

   task = kthread_run(itcThreadRunner, NULL, "ITC_timer");  
   if(IS_ERR(task)){                                     
     printk(KERN_ALERT "ITC: Thread creation failed\n");
     return PTR_ERR(task);
   }

   return 0;
}

/** @brief The LKM cleanup function
 *  Similar to the initialization function, it is static. The __exit macro notifies that if this
 *  code is used for a built-in driver (not a LKM) that this function is not required.
 */
static void __exit itc_exit(void){
   itcImplExit();

   mutex_destroy(&itc_mutex);                       // destroy the dynamically-allocated mutex
   device_destroy(itcClass, MKDEV(majorNumber, 0)); // remove the device
   class_unregister(itcClass);                      // unregister the device class
   class_destroy(itcClass);                         // remove the device class
   unregister_chrdev(majorNumber, DEVICE_NAME);     // unregister the major number
   kthread_stop(task);                              // Kill the timing thread
   printk(KERN_INFO "ITC: Bye for now.\n");
}

/** @brief The device open function that is called each time the device is opened
 *  This will only increment the numberOpens counter in this case.
 *  @param inodep A pointer to an inode object (defined in linux/fs.h)
 *  @param filep A pointer to a file object (defined in linux/fs.h)
 */
static int dev_open(struct inode *inodep, struct file *filep){

   numberOpens++;
   printk(KERN_INFO "ITC: Device has been opened %d time(s)\n", numberOpens);
   return 0;
}

/** @brief This function is called whenever device is being read from user space i.e. data is
 *  being sent from the device to the user. 
 *  @param filep A pointer to a file object (defined in linux/fs.h)
 *  @param buffer The pointer to the buffer to which this function writes the data
 *  @param len The length of the b
 *  @param offset The offset if required
 */
static ssize_t dev_read(struct file *filep, char *buffer, size_t len, loff_t *offset){
  const unsigned int MAX_BUF = 128;
  int error = 0;
  u8 infoBuffer[MAX_BUF];
  if (len > MAX_BUF) len = MAX_BUF;

  // Get the mutex (returns 0 unless interrupted)
  if((error = mutex_lock_interruptible(&itc_mutex))) return error;

  error = itcGetCurrentLockInfo(infoBuffer,len);  // ITC_MUTEX HELD

  mutex_unlock(&itc_mutex);

  if (error < 0)
    return error;

  error = copy_to_user(buffer, infoBuffer, len);

  if (!error)
    return len;

  printk(KERN_INFO "ITC: Failed to send %d characters to the user\n", error);
  return -EFAULT;      // Failed -- return a bad address message (i.e. -14)
}

/** @brief This function is called whenever the device is being
 *  written to from user space i.e.  data is sent to the device from
 *  the user. At present, one byte only is read, and interpreted as a
 *  lockset to attempt to take.
 *  @param filep A pointer to a file object
 *  @param buffer The buffer to that contains the string to write to the device
 *  @param len The length of the array of data that is being passed in the const char buffer
 *  @param offset The offset if required
 */
static ssize_t dev_write(struct file *filep, const char *buffer, size_t len, loff_t *offset){

  u8 lockCmd;
  ssize_t ret;
  u32 bytesHandled;

  /* This loop written expecting len to most often be 1 */
  for (bytesHandled = 0; bytesHandled < len; ++bytesHandled) {
    ret = copy_from_user(&lockCmd, &buffer[bytesHandled], 1);
    if (ret != 0) {
      printk(KERN_INFO "Itc: copy_from_user failed\n");
      return -EFAULT;
    }

    // Get the mutex (returns 0 unless interrupted)
    if((ret = mutex_lock_interruptible(&itc_mutex))) return ret;

    ret = itcInterpretCommandByte(lockCmd);   // ITC_MUTEX HELD

    mutex_unlock(&itc_mutex);

    if (ret < 0) {
      if (bytesHandled == 0)  // If no bytes yet written
        return ret;           // ..you get the error code
      break;                  // Otherwise you get a partial write
    }
  }

  return bytesHandled;
}

/** @brief The device release function that is called whenever the device is closed/released by
 *  the userspace program
 *  @param inodep A pointer to an inode object (defined in linux/fs.h)
 *  @param filep A pointer to a file object (defined in linux/fs.h)
 */
static int dev_release(struct inode *inodep, struct file *filep){
   mutex_unlock(&itc_mutex);                      // release the mutex (i.e., lock goes up)
   printk(KERN_INFO "ITC: Device successfully closed\n");
   return 0;
}

/** @brief A module must use the module_init() module_exit() macros from linux/init.h, which
 *  identify the initialization function at insertion time and the cleanup function (as
 *  listed above)
 */
module_init(itc_init);
module_exit(itc_exit);
