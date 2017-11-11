/*
 *
 * Copyright (C) 2017 The Regents of the University of New Mexico
 *
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

#define PRU_MAX_DEVICES 4
#define DRIVER_BUF_SIZE 1

struct rpmsg_pru_itcio_dev {
	struct rpmsg_channel *rpmsg_dev;
	struct device *dev;
	bool dev_lock;
	bool buf_lock;
	struct cdev cdev;
	dev_t devt;
};

static struct class *rpmsg_pru_itcio_class;
static dev_t rpmsg_pru_itcio_devt;

static DEFINE_IDR(rpmsg_pru_itcio_minors);



static int rpmsg_pru_itcio_open(struct inode *inode,
					   struct file *filp)
{
	int ret = -EACCES;
	struct rpmsg_pru_itcio_dev *pp_example_dev;

	pp_example_dev = container_of(inode->i_cdev,
				      struct rpmsg_pru_itcio_dev,
				      cdev);

	if (!pp_example_dev->dev_lock) {
		pp_example_dev->dev_lock = true;
		filp->private_data = pp_example_dev;
		ret = 0;
	}

	if (ret)
		dev_err(pp_example_dev->dev,
			"Failed to open already open device\n");

	return ret;
}


static ssize_t rpmsg_pru_itcio_write(struct file *filp,
						const char __user *buf,
						size_t count, loff_t *f_ops)
{
	int ret;
	static char driver_buf[DRIVER_BUF_SIZE];
	struct rpmsg_pru_itcio_dev *pp_example_dev;

	pp_example_dev = filp->private_data;

	if (!pp_example_dev->buf_lock){

		if (count > DRIVER_BUF_SIZE - sizeof(struct rpmsg_hdr)) {
			dev_err(pp_example_dev->dev, "Data larger than buffer size");
			return -EINVAL;
		}

		if (copy_from_user(driver_buf, buf, count)) {
			dev_err(pp_example_dev->dev, "Failed to copy data");
			return -EFAULT;
		}

		pp_example_dev->buf_lock = true;
		ret = rpmsg_send(pp_example_dev->rpmsg_dev, (void *)driver_buf,
				 DRIVER_BUF_SIZE*sizeof(char));
		if (ret) {
			dev_err(pp_example_dev->dev,
				"Transmission on rpmsg bus failed %d\n",ret);
			pp_example_dev->buf_lock = false;
			return -EFAULT;
		}

		dev_info(pp_example_dev->dev, "Input message : %c",
			 driver_buf[0]);
		return count;
	}

	dev_err(pp_example_dev->dev, "Buffer is locked\n");

	return -EFAULT;
}


static int rpmsg_pru_itcio_release(struct inode *inode,
					      struct file *filp)
{
	struct rpmsg_pru_itcio_dev *pp_example_dev;

	pp_example_dev = container_of(inode->i_cdev,
				      struct rpmsg_pru_itcio_dev,
				      cdev);
	pp_example_dev->buf_lock = false;
	pp_example_dev->dev_lock = false;

	return 0;
}

static const struct file_operations rpmsg_pru_itcio_fops = {
        .owner	= THIS_MODULE,
	.open	= rpmsg_pru_itcio_open,
	.write	= rpmsg_pru_itcio_write,
	.release= rpmsg_pru_itcio_release,
};


static void rpmsg_pru_itcio_cb(struct rpmsg_channel *rpmsg_dev,
					  void *data , int len , void *priv,
					  u32 src )
{
	struct rpmsg_pru_itcio_dev *pp_example_dev;

	pp_example_dev = dev_get_drvdata(&rpmsg_dev->dev);

	print_hex_dump(KERN_INFO, "incoming message:", DUMP_PREFIX_NONE, 16, 1,
		       data, len, true);

	if (pp_example_dev->buf_lock)
		pp_example_dev->buf_lock = false;
}


/*
 * driver probe function
 */

static int rpmsg_pru_itcio_probe(struct rpmsg_channel *rpmsg_dev)
{
	int ret;
	struct rpmsg_pru_itcio_dev *pp_example_dev;
	int minor_obtained;

	dev_info(&rpmsg_dev->dev, "chnl: 0x%x -> 0x%x\n", rpmsg_dev->src,
		 rpmsg_dev->dst);

	pp_example_dev = devm_kzalloc(&rpmsg_dev->dev, sizeof(*pp_example_dev),
				      GFP_KERNEL);
	if(!pp_example_dev)
		return -ENOMEM;


	minor_obtained = idr_alloc(&rpmsg_pru_itcio_minors,
				   pp_example_dev, 0, PRU_MAX_DEVICES,
				   GFP_KERNEL);

	if(minor_obtained < 0) {
		ret = minor_obtained;
		dev_err(&rpmsg_dev->dev, "Failed : couldnt get a minor number with return value %d\n",
			ret);
		goto fail_idr_alloc;
	}

	pp_example_dev->devt = MKDEV(MAJOR(rpmsg_pru_itcio_devt),
				     minor_obtained);

	cdev_init(&pp_example_dev->cdev, &rpmsg_pru_itcio_fops);
	pp_example_dev->cdev.owner = THIS_MODULE;
	ret = cdev_add(&pp_example_dev->cdev, pp_example_dev->devt,1);
	if (ret) {
		dev_err(&rpmsg_dev->dev, "Unable to init cdev\n");
		goto fail_cdev_init;
	}

	pp_example_dev->dev = device_create(rpmsg_pru_itcio_class,
					    &rpmsg_dev->dev,
					    pp_example_dev->devt, NULL, "rpmsg_pru_itcio");
	if (IS_ERR(pp_example_dev)) {
		dev_err(&rpmsg_dev->dev, "Failed to create device file entries\n");
		ret = PTR_ERR(pp_example_dev->dev);
		goto fail_device_create;
	}

	pp_example_dev->rpmsg_dev = rpmsg_dev;

	dev_set_drvdata(&rpmsg_dev->dev, pp_example_dev);
	dev_info(&rpmsg_dev->dev, "pru_itcio device ready at /dev/rpmsg_pru_itcio");

	return 0;




fail_device_create:
	cdev_del(&pp_example_dev->cdev);
fail_cdev_init:
	idr_remove(&rpmsg_pru_itcio_minors, minor_obtained);
fail_idr_alloc:
	return ret;
}


static void rpmsg_pru_itcio_remove(struct rpmsg_channel *rpmsg_dev)
{
	struct rpmsg_pru_itcio_dev *pp_example_dev;

	pp_example_dev = dev_get_drvdata(&rpmsg_dev->dev);

	device_destroy(rpmsg_pru_itcio_class, pp_example_dev->devt);
	cdev_del(&pp_example_dev->cdev);
	idr_remove(&rpmsg_pru_itcio_minors,
		   MINOR(pp_example_dev->devt));
}


static const struct rpmsg_device_id
	rpmsg_driver_pru_itcio_id_table[] = {
		{ .name = "rpmsg-pru-itcio" },
		{ },
	};
MODULE_DEVICE_TABLE(rpmsg, rpmsg_driver_pru_itcio_id_table);

static struct rpmsg_driver rpmsg_pru_itcio_driver = {
	.drv.name	= KBUILD_MODNAME,
	.drv.owner	= THIS_MODULE,
	.id_table	= rpmsg_driver_pru_itcio_id_table,
	.probe		= rpmsg_pru_itcio_probe,
	.callback	= rpmsg_pru_itcio_cb,
	.remove		= rpmsg_pru_itcio_remove,
};

static int __init rpmsg_itcio_init (void)
{
	int ret;

	rpmsg_pru_itcio_class = class_create(THIS_MODULE, "rpmsg_pru_itcio");
	if (IS_ERR(rpmsg_pru_itcio_class))
	{
		pr_err("Failed to create class\n");
		ret= PTR_ERR(rpmsg_pru_itcio_class);
		goto fail_class_create;
	}

	ret = alloc_chrdev_region(&rpmsg_pru_itcio_devt, 0,
				  PRU_MAX_DEVICES, "rpmsg_pru_itcio");
	if (ret) {
		pr_err("Failed to allocate chrdev region\n");
		goto fail_alloc_chrdev_region;
	}

	ret = register_rpmsg_driver(&rpmsg_pru_itcio_driver);
	if (ret) {
		pr_err("Failed to register the driver on rpmsg bus");
		goto fail_register_rpmsg_driver;
	}

	return 0;

fail_register_rpmsg_driver:
	unregister_chrdev_region(rpmsg_pru_itcio_devt,
				 PRU_MAX_DEVICES);
fail_alloc_chrdev_region:
	class_destroy(rpmsg_pru_itcio_class);
fail_class_create:
	return ret;
}


static void __exit rpmsg_itcio_exit (void)
{
	unregister_rpmsg_driver(&rpmsg_pru_itcio_driver);
	idr_destroy(&rpmsg_pru_itcio_minors);
	class_destroy(rpmsg_pru_itcio_class);
	unregister_chrdev_region(rpmsg_pru_itcio_devt,
				 PRU_MAX_DEVICES);
}

module_init(rpmsg_itcio_init);
module_exit(rpmsg_itcio_exit);

MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("Dave Ackley <ackley@ackleyshack.com>");
MODULE_DESCRIPTION("T2 intertile packet communications subsystem");  ///< modinfo description
MODULE_VERSION("0.2");            ///< 0.2 for initial import
