        .cdecls C,LIST
        %{
#include "Buffers.h"
#define ON_PRU 1
#include "prux.h"
        %}
       .copy "prux_sbst3.inc"
        
