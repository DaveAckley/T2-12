#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <cerrno>
#include <time.h>

#define CIODIR "/mnt/T2TMP"
//#define CIODIR "."
#define CINPUTFILE CIODIR "/input.dat"
#define COUTPUTFILE CIODIR "/output.dat"

#define USLEEPTIME 20000u  // 20ms, 50Hz

#define CBUFFERSIZE (2*256)

class BrainStem {
public:
  BrainStem()
    : _bufferLen(0u)
    , _updates(0u)
  {
    if (fstat(0,&_istat) < 0) fdie("stating","stdin"); // just to have something
    _rstat = _istat;
  }

  inline bool diffMTime(const struct stat & s1, const struct stat & s2) const {
    return
      (s1.st_mtim.tv_sec != s2.st_mtim.tv_sec) ||
      (s1.st_mtim.tv_nsec != s2.st_mtim.tv_nsec);
  }

  inline bool newInput() const {
    return diffMTime(_istat,_rstat);
  }

  void markInputConsumed() {
    _rstat = _istat;
  }

  void fdie(const char * op, const char * file) {
    fprintf(stderr,"Error %s %s: %s\n",
            op,
            file,
            strerror(errno));
    exit(1);
  }

  bool readInputFile() { // true if file exists and was read
    int fd;
    bool ret = false;
    fd = open(CINPUTFILE, O_RDONLY);
    if (fd < 0) return ret;

    struct stat nowstat;
    if (fstat(fd,&nowstat) < 0) fdie("stating",CINPUTFILE);
    
    if (diffMTime(nowstat,_istat)) {
      ret = true;
      _istat = nowstat;
      _bufferLen = read(fd,_buffer, sizeof _buffer);
      if (_bufferLen < 0) fdie("reading",CINPUTFILE);
    }
    close(fd);
    return ret;
  }

  void writeOutputFile() {
    int fd;
    fd = open(COUTPUTFILE, O_WRONLY|O_CREAT, 0644);
    if (fd < 0) {
      fprintf(stderr,"Can't write %s: %s\n",
              COUTPUTFILE,
              strerror(errno));
      exit(3);
    }
    ssize_t wrote = write(fd,_buffer, _bufferLen);
    if (wrote != _bufferLen) {
      fprintf(stderr,"Incomplete write of %s %ld vs %ld\n",
              COUTPUTFILE,_bufferLen,wrote);
      exit(4);
    }
    close(fd);
  }

  int run() {
    while (1) {
      writeOutputFile();
      readInputFile();
      usleep(USLEEPTIME);
      if (!(_updates % 1000))
        printf("Updates %lu\n",_updates);
      ++_updates;
    }
    return 0;
  }

private:
  char _buffer[CBUFFERSIZE];
  ssize_t _bufferLen;
  size_t _updates;
  struct stat _istat; // last stat time of input
  struct stat _rstat; // last stat read by routing
};

int main() {
  BrainStem bs;
  return bs.run();
  return 0;
}
