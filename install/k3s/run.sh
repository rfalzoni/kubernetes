#!/bin/bash
curl -sfL https://get.k3s.io | sh -
sleep 30
k3s kubectl get node
