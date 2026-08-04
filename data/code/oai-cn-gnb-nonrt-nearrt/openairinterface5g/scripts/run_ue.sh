#!/bin/bash

cd ../cmake_targets/ran_build/build
# sudo ./nr-uesoftmodem -O ../../../scripts/ue.conf \
#     --rfsim \
#     -r 106 \
#     --numerology 1 \
#     --band 78 \
#     -C 3619200000 \
#     --ssb 516

sudo ./nr-uesoftmodem -O ../../../scripts/ue.conf \
  --rfsim \
  -r 106 --numerology 1 --band 78 -C 3619200000 --ssb 516
