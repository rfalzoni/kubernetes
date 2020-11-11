#!/bin/bash
CLUSTER_NAME=$1

if [ -e ${CLUSTER_NAME} ]; then
  CLUSTER_NAME="demo"
fi

kind create cluster \
  --config kind-example-config.yaml \
  --name ${CLUSTER_NAME}

