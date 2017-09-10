#include "tnv.h"

int main() {
  unsigned count = 1678;
  printf("%d = %d C, %f F\n", count, getCentigradeFromCount(count), getFloatFarenheitFromCount(count));
  return 0;
}
