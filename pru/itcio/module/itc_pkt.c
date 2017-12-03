/*
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

#include <linux/kernel.h>
#include <linux/rpmsg.h>
#include <linux/slab.h>
#include <linux/fs.h>
#include <linux/init.h>
#include <linux/cdev.h>
#include <linux/module.h>
#include <linux/kfifo.h>
#include <linux/uaccess.h>
#include <linux/poll.h>

#define PRU_MAX_DEVICES 2       /* PRU0, PRU1*/
#define MINOR_DEVICES (PRU_MAX_DEVICES+1)  /* +1 for the ITC packet interface */
#define RPMSG_BUF_SIZE 512
#define MAX_PACKET_SIZE (RPMSG_BUF_SIZE-sizeof(struct rpmsg_hdr))

/* ITC packets are max 255.  Guarantee space for 16 (256*16 == 4,096 == 2**12) */
#define KFIFO_SIZE (1<<12)
#define PROC_FIFO "itc-pkt-fifo"

/* PRU special packets are expected to be smaller are rarer.  Give them 1KB each */
#define SPECIAL_KFIFO_SIZE (1<<10)

/* lock for read access (no lock for write access - rpmsg cb will be only writer) */
static DEFINE_MUTEX(read_lock);

/* REC_1 for one byte record lengths is perfect for us.. */
typedef STRUCT_KFIFO_REC_1(KFIFO_SIZE) ITCPacketFIFO;
typedef STRUCT_KFIFO_REC_1(SPECIAL_KFIFO_SIZE) SpecialPacketFIFO;

static ITCPacketFIFO itcPacketKfifo;
static SpecialPacketFIFO special0Kfifo;
static SpecialPacketFIFO special1Kfifo;
static int open_pru_minors;

struct itc_pkt_dev {
  struct rpmsg_channel *rpmsg_dev;
  struct device *dev;
  bool dev_lock;
  struct cdev cdev;
  dev_t devt;
};

static struct class *itc_pkt_class;
static dev_t itc_pkt_devt;

static struct itc_pkt_dev * iodev_itc_packet_device;

/** @brief The callback function for when the device is opened
 *  What
 *  @param inodep A pointer to an inode object (defined in linux/fs.h)
 *  @param filep A pointer to a file object (defined in linux/fs.h)
 */
static int itc_pkt_open(struct inode *inode, struct file *filp)
{
  int ret = -EACCES;
  struct itc_pkt_dev *iodev;

  iodev = container_of(inode->i_cdev, struct itc_pkt_dev, cdev);

  if (!iodev->dev_lock) {
    iodev->dev_lock = true;
    filp->private_data = iodev;
    ret = 0;
  }

  if (ret)
    dev_err(iodev->dev, "Device already open\n");
  
  return ret;
}

/** @brief The callback for when the device is closed/released by
 *  the userspace program
 *  @param inodep A pointer to an inode object (defined in linux/fs.h)
 *  @param filep A pointer to a file object (defined in linux/fs.h)
 */
static int itc_pkt_release(struct inode *inode, struct file *filp)
{
  struct itc_pkt_dev *iodev;

  iodev = container_of(inode->i_cdev, struct itc_pkt_dev, cdev);
  iodev->dev_lock = false;
  
  return 0;
}

/** @brief This callback used when data is being written to the device
 *  from user space.  This is primarily to be for MFM cache update
 *  packet transfer, but at present at this level, we're just talking
 *  about uninterpreted byte chunks (that fit in MAX_PACKET_SIZE).
 *  (Note also that MFM packets are less than 256 bytes (128?), but
 *  that is not reflected in the limits here.)
 *
 *  @param filp A pointer to a file object
 *  @param buf The buffer to that contains the data to write to the device
 *  @param count The number of bytes to write from buf
 *  @param offset The offset if required
 */

static ssize_t itc_pkt_write(struct file *filp,
                             const char __user *buf,
                             size_t count, loff_t *offset)
{
  int ret;
  static unsigned char driver_buf[RPMSG_BUF_SIZE];
  struct itc_pkt_dev *iodev;

  iodev = filp->private_data;

  if (count > MAX_PACKET_SIZE) {
    dev_err(iodev->dev, "Data larger than buffer size");
    return -EINVAL;
  }

  if (copy_from_user(driver_buf, buf, count)) {
    dev_err(iodev->dev, "Failed to copy data");
    return -EFAULT;
  }

  ret = rpmsg_send(iodev->rpmsg_dev, (void *)driver_buf, count);
  if (ret) {
    dev_err(iodev->dev,
            "Transmission on rpmsg bus failed %d\n",ret);
    return -EFAULT;
  }

  dev_info(iodev->dev,
           (driver_buf[0]&0x80)?
             "Sending length %d type 0x%02x packet" :
             "Sending length %d type '%c' packet",
           count,
           driver_buf[0]);

  return count;
}

static ssize_t itc_pkt_read(struct file *file, char __user *buf,
                            size_t count, loff_t *ppos)
{
  int ret;
  unsigned int copied;

  struct itc_pkt_dev *iodev = file->private_data;
  int minor = MINOR(iodev->devt);

  printk(KERN_INFO "read file * = %p, %d:%d", file, MAJOR(iodev->devt), minor);
  if (mutex_lock_interruptible(&read_lock))
    return -ERESTARTSYS;

  switch (minor) {
  case 0: ret = kfifo_to_user(&special0Kfifo, buf, count, &copied); break;
  case 1: ret = kfifo_to_user(&special1Kfifo, buf, count, &copied); break;
  case 2: ret = kfifo_to_user(&itcPacketKfifo, buf, count, &copied); break;
  default: BUG_ON(1);
  } 

  mutex_unlock(&read_lock);

  return ret ? ret : copied;
}


static const struct file_operations itc_pkt_fops = {
  .owner= THIS_MODULE,
  .open	= itc_pkt_open,
  .read = itc_pkt_read,
  .write= itc_pkt_write,
  .release= itc_pkt_release,
};


static void itc_pkt_cb(struct rpmsg_channel *rpmsg_dev,
                               void *data , int len , void *priv,
                               u32 src )
{
  struct itc_pkt_dev *iodev = dev_get_drvdata(&rpmsg_dev->dev);
  int minor = MINOR(iodev->devt);

  printk(KERN_INFO "Received %d from %d",len, minor);

  if (len > 255) {
    printk(KERN_ERR "Truncating overlength (%d) packet",len);
    len = 255;
  }

  print_hex_dump(KERN_INFO, "pkt:", DUMP_PREFIX_NONE, 16, 1,
                 data, len, true);

  if (len > 0) {
    // ITC data if first byte MSB set
    if ((*(char*)data)&0x80) kfifo_in(&itcPacketKfifo, data, len);
    else if (minor == 0) kfifo_in(&special0Kfifo, data, len);
    else if (minor == 1) kfifo_in(&special1Kfifo, data, len);
    else BUG_ON(1);
  }
}


static struct itc_pkt_dev * make_itc_minor(struct device * dev,
                                           int minor_obtained,
                                           int * err_ret)
{
  struct itc_pkt_dev *iodev;
  enum { BUFSZ = 16 };
  char devname[BUFSZ];
  int ret;

  BUG_ON(!err_ret);
  
  if (minor_obtained == 2)
    snprintf(devname,BUFSZ,"itc!packets");
  else
    snprintf(devname,BUFSZ,"itc!pru%d",minor_obtained);

  iodev = devm_kzalloc(dev, sizeof(*iodev), GFP_KERNEL);
  if (!iodev) {
    ret = -ENOMEM;
    goto fail_kzalloc;
  }

  iodev->devt = MKDEV(MAJOR(itc_pkt_devt), minor_obtained);

  printk(KERN_INFO "INITTING /dev/%s", devname);

  cdev_init(&iodev->cdev, &itc_pkt_fops);
  iodev->cdev.owner = THIS_MODULE;
  ret = cdev_add(&iodev->cdev, iodev->devt,1);

  if (ret) {
    dev_err(dev, "Unable to init cdev\n");
    goto fail_cdev_init;
  }

  iodev->dev = device_create(itc_pkt_class,
                             dev,
                             iodev->devt, NULL,
                             devname);
  
  if (IS_ERR(iodev->dev)) {
    dev_err(dev, "Failed to create device file entries\n");
    ret = PTR_ERR(iodev->dev);
    goto fail_device_create;
  }

  dev_set_drvdata(dev, iodev);
  dev_info(dev, "pru itc packet device ready at /dev/%s",devname);

  return iodev;
  
 fail_device_create:
  cdev_del(&iodev->cdev);

 fail_cdev_init:

 fail_kzalloc:
  *err_ret = ret;
  return 0;
}

/*
 * driver probe function
 */

static int itc_pkt_probe(struct rpmsg_channel *rpmsg_dev)
{
  int ret;
  struct itc_pkt_dev *iodev;
  int minor_obtained;

  printk(KERN_INFO "ZORG itc_pkt_probe");

  dev_info(&rpmsg_dev->dev, "chnl: 0x%x -> 0x%x\n", rpmsg_dev->src,
           rpmsg_dev->dst);

  minor_obtained = rpmsg_dev->dst - 30;
  if (minor_obtained < 0 || minor_obtained > 1) {
    dev_err(&rpmsg_dev->dev, "Failed : Unrecognized destination %d\n",
            rpmsg_dev->dst);
    return -ENODEV;
  }

  iodev = make_itc_minor(&rpmsg_dev->dev, minor_obtained, &ret);

  if (!iodev)
    return ret;
  
  iodev->rpmsg_dev = rpmsg_dev;
  ++open_pru_minors;

  /* send empty message to give PRU src & dst info*/
  ret = rpmsg_send(iodev->rpmsg_dev, "", 0);
  if (ret) {
    dev_err(iodev->dev, "Opening transmission on rpmsg bus failed %d\n",ret);
    ret = PTR_ERR(iodev->dev);
    cdev_del(&iodev->cdev);
  }

  /* If first minor, also open packet device*/
  if (open_pru_minors == 1) {

    BUG_ON(minor_obtained == 2);

    /* XXX NOT READY FOR PRIME TIME
    iodev_itc_packet_device = make_itc_minor(&rpmsg_dev->dev, 2, &ret);

    if (!iodev_itc_packet_device)
      return ret;

    iodev_itc_packet_device->rpmsg_dev = 0;
    ++open_pru_minors;
    */
  }

  return ret;
}

/* NOT USED

 if (minor_obtained != 2) {
    ret = rpmsg_send(iodev->rpmsg_dev, "HEWO", 4);
    if (ret) {
      dev_err(iodev->dev, "Opening transmission on rpmsg bus failed %d\n",ret);
      ret = PTR_ERR(iodev->dev);
      goto fail_device_create;
    } else {
*/


static void itc_pkt_remove(struct rpmsg_channel *rpmsg_dev) {
  struct itc_pkt_dev *iodev;

  iodev = dev_get_drvdata(&rpmsg_dev->dev);

  device_destroy(itc_pkt_class, iodev->devt);
  cdev_del(&iodev->cdev);
}


static const struct rpmsg_device_id rpmsg_driver_itc_pkt_id_table[] = {
  { .name = "itc-pkt" },
  { },
};

MODULE_DEVICE_TABLE(rpmsg, rpmsg_driver_itc_pkt_id_table);

static struct rpmsg_driver itc_pkt_driver = {
  .drv.name	= KBUILD_MODNAME,
  .drv.owner	= THIS_MODULE,
  .id_table	= rpmsg_driver_itc_pkt_id_table,
  .probe	= itc_pkt_probe,
  .callback	= itc_pkt_cb,
  .remove	= itc_pkt_remove,
};

static int __init itc_pkt_init (void)
{
  int ret;

  printk(KERN_INFO "ZORG itc_pkt_init");

  INIT_KFIFO(itcPacketKfifo);
  INIT_KFIFO(special0Kfifo);
  INIT_KFIFO(special1Kfifo);

  open_pru_minors = 0;

  itc_pkt_class = class_create(THIS_MODULE, "itc_pkt");
  if (IS_ERR(itc_pkt_class)) {
    pr_err("Failed to create class\n");
    ret= PTR_ERR(itc_pkt_class);
    goto fail_class_create;
  }

  ret = alloc_chrdev_region(&itc_pkt_devt, 0,
                            MINOR_DEVICES, "itc_pkt");
  if (ret) {
    pr_err("Failed to allocate chrdev region\n");
    goto fail_alloc_chrdev_region;
  }

  ret = register_rpmsg_driver(&itc_pkt_driver);
  if (ret) {
    pr_err("Failed to register the driver on rpmsg bus");
    goto fail_register_rpmsg_driver;
  }

  return 0;

 fail_register_rpmsg_driver:
  unregister_chrdev_region(itc_pkt_devt,
                           MINOR_DEVICES);
 fail_alloc_chrdev_region:
  class_destroy(itc_pkt_class);
 fail_class_create:
  return ret;
}


static void __exit itc_pkt_exit (void)
{
  unregister_rpmsg_driver(&itc_pkt_driver);
  class_destroy(itc_pkt_class);
  unregister_chrdev_region(itc_pkt_devt,
                           MINOR_DEVICES);
}

module_init(itc_pkt_init);
module_exit(itc_pkt_exit);

MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("Dave Ackley <ackley@ackleyshack.com>");
MODULE_DESCRIPTION("T2 intertile packet communications subsystem");  ///< modinfo description

MODULE_VERSION("0.3");            ///< 0.3 for renaming to itc_pkt
/// 0.2 for initial import

/////ADDITIONAL COPYRIGHT INFO

/* This software is based in part on 'rpmsg_pru_parallel_example.c',
 * which is: Copyright (C) 2016 Zubeen Tolani <ZeekHuge -
 * zeekhuge@gmail.com> and also licensed under the terms of the GNU
 * General Public License version 2.
 *
 */

/* And that software, in turn, was based on examples from the
 * 'pru-software-support-package', which includes the following:
 */

/*
 * Copyright (C) 2016 Texas Instruments Incorporated - http://www.ti.com/
 *
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *	* Redistributions of source code must retain the above copyright
 *	  notice, this list of conditions and the following disclaimer.
 *
 *	* Redistributions in binary form must reproduce the above copyright
 *	  notice, this list of conditions and the following disclaimer in the
 *	  documentation and/or other materials provided with the
 *	  distribution.
 *
 *	* Neither the name of Texas Instruments Incorporated nor the names of
 *	  its contributors may be used to endorse or promote products derived
 *	  from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */


