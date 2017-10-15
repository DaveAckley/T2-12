/**
 * @file   testitc.c
 * @author Dave Ackley
 * @date   6 October 2017
 * @version 0.1

 * @brief A Linux user space program that communicates with the
 * itc.c LKM. For this example to work the device * must be called
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

int main(){
  int ret, fd, i;
  /*  char stringToSend[BUFFER_LENGTH]; */
  printf("Starting itc device test code example...\n");
  fd = open("/dev/itc/locks", O_RDWR);             /* Open the device with read/write access */
  if (fd < 0){
    perror("Failed to open the device...");
    return errno;
  }
#if 0   
   printf("Type in a short string to send to the kernel module:\n");
   scanf("%[^\n]%*c", stringToSend);              /* Read in a string (with spaces) */
   printf("Writing message to the device [%s].\n", stringToSend);
   ret = write(fd, stringToSend, strlen(stringToSend)); /* Send the string to the LKM */
   if (ret < 0){
      perror("Failed to write the message to the device.");
      return errno;
   }

   printf("Press ENTER to read back from the device...");
   getchar();
#endif

   ret = read(fd, receive, 4);        /* Read the response from the LKM */
   if (ret < 0){
     perror("Failed to read the message from the device.");
     return errno;
   }
   printf("Read 4 got %d: ", ret);
   for (i = 0; i < ret; ++i) {
     if (i) printf(", ");
     printf("%d = 0x%02x",i,receive[i]);
   }
   printf("\n");
   ret = close(fd);
   if (ret < 0){
     perror("Close failed.");
     return errno;
   }
   return 0;
}
