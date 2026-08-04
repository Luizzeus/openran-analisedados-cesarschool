#!/bin/bash

cd ../cmake_targets/ran_build/build
sudo ./nr-softmodem -O ../../../scripts/gnb.conf\
    --gNBs.[0].min_rxtxtime 6 \
    --rfsim
