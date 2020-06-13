#!/bin/bash
SECONDS=0

SERVERS=$(multipass list | grep -E "^dns|^loadbalancer|^master|^worker" | awk '{ print $1 }')

for SERVER in ${SERVERS}; do
  echo ${SERVER}
  multipass delete ${SERVER}
done

multipass purge

printf '%d hour %d minute %d seconds\n' $((${SECONDS}/3600)) $((${SECONDS}%3600/60)) $((${SECONDS}%60))
