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
#define CINPUTFILE (CIODIR "/input.dat")
#define COUTPUTFILE (CIODIR "/output.dat")
#define CTAGSFILE (CIODIR "/tags.dat")

#define USLEEPTIME 20000u  // 20ms, 50Hz

#define CBUFFERSIZE (2*256)
#define MAXTAGNAMELEN 15
#define MAXTAGCOUNT 256

#define INHIBITIONBASE 100

class BrainStem {
public:
  BrainStem()
    : _bufferLen(0u)
    , _updates(0u)
    , _routed(0u)
    , _tagCount(0u)
    , _bvcodeVal(0u)
  {
    if (fstat(0,&_istat) < 0) fdie("stating","stdin"); // just to have something
    _rstat = _istat;
    _tstat = _istat;
  }

  inline bool diffMTime(const struct stat & s1, const struct stat & s2) const {
    return
      (s1.st_mtim.tv_sec != s2.st_mtim.tv_sec) ||
      (s1.st_mtim.tv_nsec != s2.st_mtim.tv_nsec);
  }

  bool tryLoadTags() {
    bool ret = false;
    int fd = open(CTAGSFILE, O_RDONLY);
    if (fd < 0) return ret;

    struct stat nowstat;
    if (fstat(fd,&nowstat) < 0) fdie("stating",CTAGSFILE);
    
    if (_tagCount == 0u || diffMTime(nowstat,_tstat)) { // if no or new tags, load
      readTags(fd);
      _tstat = nowstat;
      ret = true;
    }

    close(fd);
    return ret;
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

  int getTagIndex(const char * tag) {
    for (unsigned i = 0u; i < _tagCount; ++i) {
      if (0==strncmp(tag,(const char *) &_tags[i].mTagName,MAXTAGNAMELEN))
        return (int) i;
    }
    return -1;
  }

  int bufferPosOfTagIndex(int tagidx) {
    for (unsigned i = 0u; i < _bufferLen; i += 2u) {
      if (_buffer[i] == (unsigned) tagidx)
        return (int) i;
    }
    return -1;
  }

  unsigned char inhibition(unsigned char inhibitor) {
    if (inhibitor >= INHIBITIONBASE) return 0u;
    return (unsigned char) (INHIBITIONBASE - inhibitor);
  }

  void tryRouting() {
    bool routed = false;

    int bvcodeIdx = getTagIndex("BVCODE");
    if (bvcodeIdx < 0) return;
    int bvcodePos = bufferPosOfTagIndex(bvcodeIdx);
    if (bvcodePos  < 0) return;
    _bvcodeVal = _buffer[bvcodePos+1];

    int mlr = getTagIndex("MLR");
    int mrr = getTagIndex("MRR");
    int slfl = getTagIndex("SLFL");
    int srfl = getTagIndex("SRFL");
    if (mlr < 0 || mrr < 0 || slfl < 0 || srfl < 0) return;

    int imlr = bufferPosOfTagIndex(mlr);
    int isrfl = bufferPosOfTagIndex(srfl);
    int imrr = bufferPosOfTagIndex(mrr);
    int islfl = bufferPosOfTagIndex(slfl);

    if (imlr < 0 || imrr < 0 || islfl < 0 || isrfl < 0) return;

    switch (_bvcodeVal) {
    case 0u: {                            // BV 2A
      _buffer[imlr+1] = _buffer[islfl+1]; // slfl -> +mlr
      _buffer[imrr+1] = _buffer[isrfl+1]; // srfl -> +mrr
      routed = true;
      break;
    }

    case 1u: {                            // BV 2b
      _buffer[imlr+1] = _buffer[isrfl+1]; // srfl -> +mlr
      _buffer[imrr+1] = _buffer[islfl+1]; // srfl -> +mrr
      routed = true;
      break;
    }

    case 2u: {                                        // BV 3a
      _buffer[imlr+1] = inhibition(_buffer[islfl+1]); // slfl -> -mlr
      _buffer[imrr+1] = inhibition(_buffer[isrfl+1]); // srfl -> -mrr
      routed = true;
      break;
    }

    case 3u: {                                        // BV 3b
      _buffer[imlr+1] = inhibition(_buffer[isrfl+1]); // srfl -> -mlr
      _buffer[imrr+1] = inhibition(_buffer[islfl+1]); // slfl -> -mrr
      routed = true;
      break;
    }

    default:
      break;
    }
    if (routed) ++_routed;
  }

  int run() {
    while (1) {
      tryLoadTags();
      if (readInputFile())
        tryRouting();
      writeOutputFile();
      usleep(USLEEPTIME);
      if (!(_updates % 1000))
        printf("Updates %lu, %lu routed, code %u\n",_updates,_routed,_bvcodeVal);
      ++_updates;
    }
    return 0;
  }

  void readTags(int fd) {
    memset(&_tags,0,sizeof(_tags));
    
    _tagCount = 0u;
    bool more = true;
    while (more) {
      char c;
      ssize_t num = read(fd,&c,1u);
      if (num!=1) break; // eof or error
      TagType tt = TAGOTHER;
      if (c == '>') tt = TAGSENSE;
      else if (c == '<') tt = TAGMOTOR;
      _tags[_tagCount].mTagType = tt;
      int i = 0;
      while (i < MAXTAGNAMELEN-1) {
        num = read(fd,&c,1u);
        if (num!=1) {
          more = false;
          break;
        }
        if (c == '\n') break;
        _tags[_tagCount].mTagName[i] = c;
        ++i;
      }
      printf("Tag%d:%u,%s\n",
             _tagCount,
             _tags[_tagCount].mTagType,
             _tags[_tagCount].mTagName);
      ++_tagCount;
      if (_tagCount >= MAXTAGCOUNT) // wtf?
        exit(99);
    }
  }

  bool readTagsFile() {
    int fd;
    bool ret = false;
    fd = open(CTAGSFILE, O_RDONLY);
    if (fd < 0) return ret;

    struct stat nowstat;
    if (fstat(fd,&nowstat) < 0) fdie("stating",CTAGSFILE);
    
    if (diffMTime(nowstat,_tstat)) {
      ret = true;
      _tstat = nowstat;
      readTags(fd);
    }
    close(fd);
    return ret;
    return false;
  }

private:
  unsigned char _buffer[CBUFFERSIZE];
  ssize_t _bufferLen;
  size_t _updates;
  size_t _routed;
  struct stat _istat; // last stat read by input
  struct stat _rstat; // last stat read by routing
  
  enum TagType { TAGOTHER, TAGSENSE, TAGMOTOR }; // TAGOTHER == 0u
  typedef struct tag {
    TagType mTagType;
    char mTagName[MAXTAGNAMELEN];
  } Tag;

  struct stat _tstat; // last stat time of tags load
  Tag _tags[MAXTAGCOUNT];
  unsigned _tagCount;
  unsigned char _bvcodeVal;        // current routing code
};

int main() {
  BrainStem bs;
  printf("sizeof(BrainStem)=%lu\n",sizeof(bs));
  return bs.run();
  return 0;
}
