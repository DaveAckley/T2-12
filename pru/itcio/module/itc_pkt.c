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

#include "itc_pkt.h"

static ITCPacketDriverState S;

static void initITCPacketDriverState(ITCPacketDriverState *s)
{
  INIT_KFIFO(s->itcPacketKfifo);
  INIT_KFIFO(s->special0Kfifo);
  INIT_KFIFO(s->special1Kfifo);
  mutex_init(&s->read_lock);
  s->open_pru_minors = 0;
  s->dev_packet_state = 0;
}

/*CLASS ATTRIBUTE STUFF*/
static ssize_t itc_pkt_class_store_poke(struct class *c,
                                        struct class_attribute *attr,
                                        const char *buf,
                                        size_t count)
{
  unsigned poker;
  if (sscanf(buf,"%u",&poker) == 1) {
    printk(KERN_INFO "store poke %u\n",poker);
    return count;
  }
  return -EINVAL;
}

static ssize_t itc_pkt_class_read_packet(struct class *c,
                                         struct class_attribute *attr,
                                         char *buf)
{
  sprintf(buf,"62&0");
  return strlen(buf);
}

static ssize_t itc_pkt_class_store_packet(struct class *c,
                                          struct class_attribute *attr,
                                          const char *buf,
                                          size_t count)
{
  unsigned poker;
  char dest;
  if (count == 0) return -EINVAL;

  dest = buf[0];
  if ((dest & 0x80) == 0) return -EINVAL;

  dest &= 0x7;
  if (dest == 7) return -ENODEV;
  
  if (sscanf(buf,"%u",&poker) == 1) {
    printk(KERN_INFO "store pop %u\n",poker);
    return count;
  }
  return -EINVAL;
}

static struct class_attribute itc_pkt_class_attrs[] = {
  __ATTR(poke, 0200, NULL, itc_pkt_class_store_poke),
  __ATTR(packet, 0644, itc_pkt_class_read_packet, itc_pkt_class_store_packet),
  __ATTR_NULL,
};

/** @brief The callback function for when the device is opened
 *  What
 *  @param inodep A pointer to an inode object (defined in linux/fs.h)
 *  @param filep A pointer to a file object (defined in linux/fs.h)
 */
static int itc_pkt_open(struct inode *inode, struct file *filp)
{
  int ret = -EACCES;
  ITCDeviceState * devstate;

  devstate = container_of(inode->i_cdev, ITCDeviceState, cdev);

  if (!devstate->dev_lock) {
    devstate->dev_lock = true;
    filp->private_data = devstate;
    ret = 0;
  }

  if (ret)
    dev_err(devstate->dev, "Device already open\n");
  
  return ret;
}

/** @brief The callback for when the device is closed/released by
 *  the userspace program
 *  @param inodep A pointer to an inode object (defined in linux/fs.h)
 *  @param filep A pointer to a file object (defined in linux/fs.h)
 */
static int itc_pkt_release(struct inode *inode, struct file *filp)
{
  ITCDeviceState *devstate;

  devstate = container_of(inode->i_cdev, ITCDeviceState, cdev);
  devstate->dev_lock = false;
  
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
  ITCDeviceState *devstate;

  devstate = filp->private_data;

  if (count > MAX_PACKET_SIZE) {
    dev_err(devstate->dev, "Data larger than buffer size");
    return -EINVAL;
  }

  if (copy_from_user(driver_buf, buf, count)) {
    dev_err(devstate->dev, "Failed to copy data");
    return -EFAULT;
  }

  ret = rpmsg_send(devstate->rpmsg_dev, (void *)driver_buf, count);
  if (ret) {
    dev_err(devstate->dev,
            "Transmission on rpmsg bus failed %d\n",ret);
    return -EFAULT;
  }

  dev_info(devstate->dev,
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

  ITCDeviceState *devstate = file->private_data;
  int major = MAJOR(devstate->devt);
  int minor = MINOR(devstate->devt);

  printk(KERN_INFO "read file * = %p, %d:%d\n", file, major, minor);
  if (mutex_lock_interruptible(&S.read_lock))
    return -ERESTARTSYS;

  switch (minor) {
  case 0: ret = kfifo_to_user(&S.special0Kfifo, buf, count, &copied); break;
  case 1: ret = kfifo_to_user(&S.special1Kfifo, buf, count, &copied); break;
  case 2: ret = kfifo_to_user(&S.itcPacketKfifo, buf, count, &copied); break;
  default: BUG_ON(1);
  } 

  mutex_unlock(&S.read_lock);

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
  ITCDeviceState * devstate = dev_get_drvdata(&rpmsg_dev->dev);
  int minor = MINOR(devstate->devt);

  printk(KERN_INFO "Received %d from %d\n",len, minor);

  if (len > 255) {
    printk(KERN_ERR "Truncating overlength (%d) packet\n",len);
    len = 255;
  }

  print_hex_dump(KERN_INFO, "pkt:", DUMP_PREFIX_NONE, 16, 1,
                 data, len, true);

  if (len > 0) {
    // ITC data if first byte MSB set
    if ((*(char*)data)&0x80) kfifo_in(&S.itcPacketKfifo, data, len);
    else if (minor == 0) kfifo_in(&S.special0Kfifo, data, len);
    else if (minor == 1) kfifo_in(&S.special1Kfifo, data, len);
    else BUG_ON(1);
  }
}

/*
 * driver probe function
 */

static int itc_pkt_probe(struct rpmsg_channel *rpmsg_dev)
{
  int ret;
  ITCDeviceState *devstate;
  int minor_obtained;

  printk(KERN_INFO "ZORG itc_pkt_probe dev=%p\n",&rpmsg_dev->dev);

  dev_info(&rpmsg_dev->dev, "chnl: 0x%x -> 0x%x\n", rpmsg_dev->src,
           rpmsg_dev->dst);

  minor_obtained = rpmsg_dev->dst - 30;
  if (minor_obtained < 0 || minor_obtained > 1) {
    dev_err(&rpmsg_dev->dev, "Failed : Unrecognized destination %d\n",
            rpmsg_dev->dst);
    return -ENODEV;
  }

  /* If first minor, first open packet device*/
  if (S.open_pru_minors == 0) {

    BUG_ON(minor_obtained == 2);

    S.dev_packet_state = make_itc_minor(&rpmsg_dev->dev, 2, &ret);

    printk(KERN_INFO "GROZ made minor 2=%p SLORG\n",S.dev_packet_state);

    if (!S.dev_packet_state)
      return ret;

    S.dev_packet_state->rpmsg_dev = 0;
    ++S.open_pru_minors;
  }


  devstate = make_itc_minor(&rpmsg_dev->dev, minor_obtained, &ret);

  if (!devstate)
    return ret;
  
  devstate->rpmsg_dev = rpmsg_dev;
  ++S.open_pru_minors;

  /* send empty message to give PRU src & dst info*/
  ret = rpmsg_send(devstate->rpmsg_dev, "", 0);
  if (ret) {
    dev_err(devstate->dev, "Opening transmission on rpmsg bus failed %d\n",ret);
    ret = PTR_ERR(devstate->dev);
    cdev_del(&devstate->cdev);
  }

  return ret;
}

static const struct rpmsg_device_id rpmsg_driver_itc_pkt_id_table[] = {
  { .name = "itc-pkt" },
  { },
};

MODULE_DEVICE_TABLE(rpmsg, rpmsg_driver_itc_pkt_id_table);

static ssize_t itc_pkt_show_ET_TXRDY(struct device *dev,
                                     struct device_attribute *attr,
                                     char * buf)
{
  ITCDeviceState *itc = dev_get_drvdata(dev);
  return sprintf(buf,"HI FROM %p (ET_TXRDY)\n", itc);
}

static ssize_t itc_pkt_store_ET_TXRDY(struct device *dev,
                                      struct device_attribute *attr,
                                      const char * buf,
                                      size_t size)
{
  ITCDeviceState *itc = dev_get_drvdata(dev);
  printk(KERN_INFO "HI STORE %p (ET_TXRDY)(%s/%u)\n",
         itc,buf,size);
  return size;
}
    
static DEVICE_ATTR(ET_TXRDY, 0644, itc_pkt_show_ET_TXRDY, itc_pkt_store_ET_TXRDY);

static ssize_t itc_pkt_read_poop_data(struct file *filp, struct kobject *kobj,
                                      struct bin_attribute *attr,
                                      char *buffer, loff_t offset, size_t count)
{
  BUG_ON(!kobj);
  printk(KERN_INFO "read poop data kobject %p\n", kobj);

  if (offset) return 0;
  
  snprintf(buffer,count,"P0123456789oop");

  return strlen(buffer);
}

static ssize_t itc_pkt_write_poop_data(struct file *filp, struct kobject *kobj,
                                       struct bin_attribute *attr,
                                       char *buffer, loff_t offset, size_t count)
{
  printk(KERN_INFO "write poop data kobject %p/(%s/%u)\n", kobj,buffer,count);

  return count;
}

static BIN_ATTR(poop_data, 0644, itc_pkt_read_poop_data, itc_pkt_write_poop_data, 0);

/*DEVICE ATTRIBUTE STUFF*/
static struct attribute *itc_pkt_attrs[] = {
  &dev_attr_ET_TXRDY.attr,
  NULL,
};

static struct bin_attribute * itc_pkt_bin_attrs[] = {
  &bin_attr_poop_data,
  NULL,
};

static const struct attribute_group itc_pkt_group = {
  .attrs = itc_pkt_attrs, 
  .bin_attrs = itc_pkt_bin_attrs, 
};

static const struct attribute_group * itc_pkt_groups[] = {
  &itc_pkt_group, 
  NULL,
};

static struct class itc_pkt_class_instance = {
  .name = "itc_pkt",
  .owner = THIS_MODULE,
  .class_attrs = itc_pkt_class_attrs,
  .dev_groups = itc_pkt_groups,
};

ITCDeviceState * make_itc_minor(struct device * dev,
                                int minor_obtained,
                                int * err_ret)
{
  ITCDeviceState * devstate;
  enum { BUFSZ = 16 };
  char devname[BUFSZ];
  int ret;

  BUG_ON(!err_ret);
  
  if (minor_obtained == 2)
    snprintf(devname,BUFSZ,"itc!packets");
  else
    snprintf(devname,BUFSZ,"itc!pru%d",minor_obtained);

  devstate = devm_kzalloc(dev, sizeof(*devstate), GFP_KERNEL);
  if (!devstate) {
    ret = -ENOMEM;
    goto fail_kzalloc;
  }

  devstate->devt = MKDEV(MAJOR(S.major_devt), minor_obtained);

  printk(KERN_INFO "INITTING /dev/%s\n", devname);

  cdev_init(&devstate->cdev, &itc_pkt_fops);
  devstate->cdev.owner = THIS_MODULE;
  ret = cdev_add(&devstate->cdev, devstate->devt,1);

  if (ret) {
    dev_err(dev, "Unable to init cdev\n");
    goto fail_cdev_init;
  }

  devstate->dev = device_create(&itc_pkt_class_instance,
                                dev,
                                devstate->devt, NULL,
                                devname);
  
  if (IS_ERR(devstate->dev)) {
    dev_err(dev, "Failed to create device file entries\n");
    ret = PTR_ERR(devstate->dev);
    goto fail_device_create;
  }

  dev_set_drvdata(dev, devstate);
  dev_info(dev, "pru itc packet device ready at /dev/%s",devname);

  return devstate;
  
 fail_device_create:
  cdev_del(&devstate->cdev);

 fail_cdev_init:

 fail_kzalloc:
  *err_ret = ret;
  return 0;
}

static void itc_pkt_remove(struct rpmsg_channel *rpmsg_dev) {
  ITCDeviceState *devstate;

  devstate = dev_get_drvdata(&rpmsg_dev->dev);

  device_destroy(&itc_pkt_class_instance, devstate->devt);
  cdev_del(&devstate->cdev);
}

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

  printk(KERN_INFO "ZORG itc_pkt_init\n");

  initITCPacketDriverState(&S);

  ret = class_register(&itc_pkt_class_instance);
  if (ret) {
    pr_err("Failed to register class\n");
    goto fail_class_register;
  }

  /*  itc_pkt_class_instance.dev_groups = itc_pkt_groups;   */

  ret = alloc_chrdev_region(&S.major_devt, 0,
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
  unregister_chrdev_region(S.major_devt,
                           MINOR_DEVICES);
 fail_alloc_chrdev_region:
  class_unregister(&itc_pkt_class_instance);
 fail_class_register:
  return ret;
}


static void __exit itc_pkt_exit (void)
{
  if (S.dev_packet_state) {
    device_destroy(&itc_pkt_class_instance, S.dev_packet_state->devt);
  }

  unregister_rpmsg_driver(&itc_pkt_driver);
  class_unregister(&itc_pkt_class_instance);
  unregister_chrdev_region(S.major_devt,
                           MINOR_DEVICES);
}

module_init(itc_pkt_init);
module_exit(itc_pkt_exit);

MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("Dave Ackley <ackley@ackleyshack.com>");
MODULE_DESCRIPTION("T2 intertile packet communications subsystem");  ///< modinfo description

MODULE_VERSION("0.4");            ///< 0.4 for general internal renaming and reorg
/// 0.3 for renaming to itc_pkt
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


