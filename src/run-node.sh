#!/bin/bash

export REDIS_PORT=8888
export NODE_ADM_PORT=50000
export SERVER_ADM_PORT=50001
export INET=wlan0

./entrypoint.tcl
