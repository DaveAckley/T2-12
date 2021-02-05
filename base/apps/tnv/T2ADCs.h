/* -*- C++ -*- */
#ifndef T2ADCS_H
#define T2ADCS_H

#include <stdio.h> /*for fprintf*/
#include <errno.h> /*for errno*/
#include <string.h> /*for sterror*/
#include <stdlib.h> /*for abort*/

#include "t2adc.h" /*for gridVoltage, etc*/

#define T2ADC_CHANNEL_COUNT 7

namespace MFM {

  struct T2ADCs {
#define ALL_ADC_CHANNELS_MACRO()                                        \
    XX(GRDVLT_A,"grid voltage",gridVoltage(count))                      \
    XX(CTRTMP_A,"tile center temp",getFloatFarenheitFromCount(count))   \
    XX(EDGTMP_A,"tile edge temp",getFloatFarenheitFromCount(count))     \
    XX(ADCRSRV2,"reserved 1",count)                                     \
    XX(ADCRSRV1,"reserved 2",count)                                     \
    XX(USER_ACT,"user button pressed",((count<2000) ? 1.0 : 0.0))       \
    XX(ADCLIGHT,"light sensor",count)                                   \

    enum ADCChannel {
#define XX(a,b,c) ADC_CHNL_##a,
          ALL_ADC_CHANNELS_MACRO()
#undef XX
          COUNT_ADC_CHNL
    };

    const char * getChannelName(ADCChannel chnl) {
      switch (chnl) {
#define XX(a,b,c) case ADC_CHNL_##a: return "ADC_"#a;
        ALL_ADC_CHANNELS_MACRO()
#undef XX
      default: return "Illegal ADC channel";
      }
    }

    const char * getChannelDescription(ADCChannel chnl) {
      switch (chnl) {
#define XX(a,b,c) case ADC_CHNL_##a: return b;
        ALL_ADC_CHANNELS_MACRO()
#undef XX
      default: return "Illegal ADC channel";
      }
    }

    unsigned getChannelRawData(ADCChannel chnl) {
      if (chnl < 0 || chnl >= COUNT_ADC_CHNL) return -1;
      return mRawData[chnl];
    }

    double getChannelValue(ADCChannel chnl) {
      if (chnl < 0 || chnl >= COUNT_ADC_CHNL) return -1;
      unsigned count = mRawData[chnl];
      switch (chnl) {
      default:  // shut up compiler
#define XX(a,b,c) case ADC_CHNL_##a: return c;
        ALL_ADC_CHANNELS_MACRO()
#undef XX
      }
    }

    T2ADCs()
    {
      for (unsigned i = 0; i < T2ADC_CHANNEL_COUNT; ++i) {
        const int BUF_SIZE = 256;
        char buffer[BUF_SIZE];
        snprintf(buffer,BUF_SIZE,
                 "/sys/bus/iio/devices/iio:device0/in_voltage%d_raw",i);
        FILE * f = fopen(buffer, "r");
        if (!f) {
          fprintf(stderr,"Can't open %s: %s", buffer, strerror(errno));
          abort();
        }
        mChannels[i] = f;
        mRawData[i] = 0;
      }
    }

    bool updateChannel(ADCChannel chnl) {
      if (chnl < 0 || chnl >= COUNT_ADC_CHNL) return false;
      FILE * f = mChannels[chnl];
      fflush(f);
      fseek(f, 0, SEEK_SET);
      if (fscanf(f,"%u",&mRawData[chnl]) != 1) {
        fprintf(stderr,"Read failure on ADC channel %u", chnl);
        return false;
      }
      return true;
    }

    void update() {
      for (unsigned i = 0; i < T2ADC_CHANNEL_COUNT; ++i) {
        if (!updateChannel((ADCChannel) i))
          abort();
      }      
    }

    ~T2ADCs() {
      for (unsigned i = 0; i < T2ADC_CHANNEL_COUNT; ++i) {
        fclose(mChannels[i]);
        mChannels[i] = 0;
      }
    }

    FILE * mChannels[T2ADC_CHANNEL_COUNT];
    unsigned mRawData[T2ADC_CHANNEL_COUNT];
  };
}

#endif /* T2ADCS_H */
