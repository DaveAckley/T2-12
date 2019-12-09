#ifndef RPMSG_T2_LOCAL_H
#define RPMSG_T2_LOCAL_H

/*** FROM LINUX v4.14.108 drivers/rpmsg/virtio_rpmsg_bus.c ***/

/**
 * struct rpmsg_hdr - common header for all rpmsg messages
 * @src: source address
 * @dst: destination address
 * @reserved: reserved for future use
 * @len: length of payload (in bytes)
 * @flags: message flags
 * @data: @len bytes of message payload data
 *
 * Every message sent(/received) on the rpmsg bus begins with this header.
 */
struct rpmsg_hdr {
  u32 src;
  u32 dst;
  u32 reserved;
  u16 len;
  u16 flags;
  u8 data[0];
} __packed;

#endif /* RPMSG_T2_LOCAL_H */
