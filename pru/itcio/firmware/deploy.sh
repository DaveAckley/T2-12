#!/bin/bash
export PRU_CORE=0
./deploy_prux.sh
export PRU_CORE=1
./deploy_prux.sh
