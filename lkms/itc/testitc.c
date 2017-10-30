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
static unsigned char receive[BUFFER_LENGTH];     /** The receive buffer from the LKM */
#define DEVICE_NAME "/dev/itc/locks"

void dieNeg(int val, char * msg)
{
  if (val < 0) {
    perror(msg);
    exit(-val);
  }
}

static char * dirnames[6] = { "ET", "SE", "SW", "WT", "NW", "NE" };
static char * rdinfo[] = { "held", "unst", "givn", "idle", "fail", "rset" };
void printFlags(unsigned char ch) {
  int i;
  int seen = 0;
  for (i=0; i < 6; ++i) {
    if ((ch&(1<<i))) {
      if (seen++) printf(",");
      printf("%s",dirnames[i]);
    }
  }
}

void reportStatus(int fd)
{
  int i, ret;
  ret = read(fd, receive, 6);        /* Read the response from the LKM */
  dieNeg(ret,"read");

  printf("Read 6 got %d: ", ret);
  for (i = 0; i < ret; ++i) {
    unsigned char b = receive[i];
    if (i) printf(" ");
    printf("%s[",rdinfo[i]);
    printFlags(b);
    printf("]");
  }
  printf("\n");
}

void writeLockRequest(int fd, int lockbits)
{
  int ret;
  char buf;
  buf = lockbits; /* go for specified locks */
      
  ret = write(fd, &buf, 1);
  if (ret < 0) {
    char msg[200];
    sprintf(msg,"Write '\\%03o' failed",buf);
    dieNeg(ret,msg);
  }
  printf("Write '\\%03o' returned %d\n",buf,ret);
}

void multimode(int fd, int count) {
  int i, ret;
  for (i = 0; i < count; ++i) {
    unsigned char byte = rand()&077;
    ret = write(fd, &byte, 1);
    dieNeg(ret,"multimode write");
  }
}

int main(int argc, char ** argv){
  int fd, lockbits;
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

  fd = open(DEVICE_NAME, O_RDWR);             /* Open the device with read/write access */
  dieNeg(fd,"open " DEVICE_NAME);

  if (lockbits > 077)
    multimode(fd,lockbits);
  else {
    writeLockRequest(fd,lockbits);
    reportStatus(fd);
  }

  dieNeg(close(fd),"close");

  return 0;
}
