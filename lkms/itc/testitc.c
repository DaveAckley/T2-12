/**
 * @file   testitc.c
 * @author Dave Ackley
 * @date   6 October 2017
 * @version 0.1

 * @brief A Linux user space program that communicates with the itc.c
 * LKM. For this example to work the device must be called
 * /dev/itlocks.

 * @see itc.c
*/
#include<stdio.h>
#include<stdlib.h>
#include<errno.h>
#include<fcntl.h>
#include<string.h>
#include<unistd.h>

#define BUFFER_LENGTH 256               /** The buffer length (crude but fine) */
static char receive[BUFFER_LENGTH];     /** The receive buffer from the LKM */
#define DEVICE_NAME "/dev/itc/locks"

int main(int argc, char ** argv){
  int ret, fd, lockbits;
  char * progname = *argv++;
  if (--argc != 1) {
    printf("Usage: %s LOCKBITS-IN-OCTAL\n",progname);
    exit(1);
  }
  {
    char * end;
    lockbits = strtol(argv[0],&end,8);
    if (*end) {
      printf("Crap in octal arg '%s'\n",end);
      exit(2);
    }
  }
  
  printf("Starting itc device test code example...\n");
  fd = open(DEVICE_NAME, O_RDWR);             /* Open the device with read/write access */
  if (fd < 0) {
    perror("Failed to open " DEVICE_NAME);
    return errno;
  }

  {
    char buf[2];
    buf[0] = lockbits; /* go for specified locks */

    ret = write(fd, buf, 1);
    if (ret < 0) {
      char msg[200];
      sprintf(msg,"Write '\\%03o' failed",buf[0]);
      perror(msg);
    }
    else 
      printf("Write '\\%03o' returned %d\n",buf[0],ret);
  }

#if 0
  {
    int i;
    for (i = 0; i < 5; ++i) {
      unsigned char bufi = i;
      if (i==4) bufi |= 0x40; /* make illegal for test */
      ret = write(fd, &bufi, 1);
      if (ret < 0) {
        perror("Write failed");
        continue;
      }
    }
  }
#endif

  {
    int i, j;
    for (j = 0; j < 5; ++j) {
      ret = read(fd, receive, 6);        /* Read the response from the LKM */
      if (ret < 0){
        perror("Failed to read the message from the device.");
        return errno;
      }
      printf("Read 6 got %d: ", ret);
      for (i = 0; i < ret; ++i) {
        if (i) printf(", ");
        printf("%d = 0x%02x",i,receive[i]);
      }
      printf("\n");
    }
  }

   ret = close(fd);
   if (ret < 0){
     perror("Close failed.");
     return errno;
   }
   return 0;
}
