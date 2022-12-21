# Configure Bash Completion
cat <<EOF | tee --append ~/.bashrc

source <(kubectl completion bash)
alias k=kubectl
complete -F __start_kubectl k
EOF
source ~/.bashrc

# WARNING: We should run these commands ONLY on master-1
KUBERNETES_DESIRED_VERSION='1.25' && \
KUBERNETES_VERSION="$(apt-cache madison kubeadm \
| grep ${KUBERNETES_DESIRED_VERSION} \
| head -1 \
| awk '{ print $3 }')" && \
KUBERNETES_BASE_VERSION="${KUBERNETES_VERSION%-*}" && \
LOCAL_IP_ADDRESS=$(grep $(hostname --short) /etc/hosts | awk '{ print $1 }') && \
LOAD_BALANCER_PORT='6443' && \
LOAD_BALANCER_NAME='loadbalancer' && \
CONTROL_PLANE_ENDPOINT="${LOAD_BALANCER_NAME}:${LOAD_BALANCER_PORT}" && \
CONTROL_PLANE_ENDPOINT_TEST=$(nc -d ${LOAD_BALANCER_NAME} ${LOAD_BALANCER_PORT} && echo "OK" || echo "FAIL") && \
clear && \
echo "" && \
echo "LOCAL_IP_ADDRESS...........: ${LOCAL_IP_ADDRESS}" && \
echo "CONTROL_PLANE_ENDPOINT.....: ${CONTROL_PLANE_ENDPOINT} [${CONTROL_PLANE_ENDPOINT_TEST}]" && \
echo "KUBERNETES_BASE_VERSION....: ${KUBERNETES_BASE_VERSION}" && \
echo ""

# Initialize master-1 (=~ 1 minute 30 seconds) - check: http://loadbalancer.example.com/stats
KUBEADM_LOG_FILE="${HOME}/kubeadm-init.log" && \
NODE_NAME=$(hostname --short) && \
sudo kubeadm init \
  --v 1 \
  --node-name "${NODE_NAME?}" \
  --apiserver-advertise-address "${LOCAL_IP_ADDRESS?}" \
  --kubernetes-version "${KUBERNETES_BASE_VERSION?}" \
  --control-plane-endpoint "${CONTROL_PLANE_ENDPOINT?}" \
  --upload-certs | tee "${KUBEADM_LOG_FILE?}"

# Config
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Watch Nodes and Pods from kube-system namespace
watch -n 3 'kubectl get nodes,pods,services -o wide -A'

# Install CNI Plugin
# https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/#pod-network
# kubectl apply -f "https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml"
kubectl apply -f "https://projectcalico.docs.tigera.io/manifests/calico.yaml"

# (Another terminal) Watch Interfaces and Route information
./watch-for-interfaces-and-routes.sh

# Retrieve token information from log file
KUBEADM_LOG_FILE="${HOME}/kubeadm-init.log" && \
grep '\-\-certificate-key' "${KUBEADM_LOG_FILE?}" --before 2 | grep \
  --only-matching \
  --extended-regexp '\-\-.*' | sed \
    -e 's/\-\-control-plane //' \
    -e 's/^\-\-//' \
    -e 's/ \\$//' \
    -e 's/^.* /\U&/' \
    -e 's/\-/_/g' \
    -e 's/ /=/' \
    -e 's/^/export KUBEADM_/'

# [PASTE HERE] Execute on master-2 and master-3 and on all workers
cat <<EOF > kubeadm-tokens
export KUBEADM_TOKEN=fn2a44.cs8rkmwtqinnd8te
export KUBEADM_DISCOVERY_TOKEN_CA_CERT_HASH=sha256:f58f31412774491d5a80ac5621d6ef27c29093769872c72100ceca37c9917fbe
export KUBEADM_CERTIFICATE_KEY=bba0f8e4157ec30acadab3639d5d265140e3875f9920af129f930df450174057
EOF

# Join Command Variables
source kubeadm-tokens

NODE_NAME=$(hostname --short) && \
LOCAL_IP_ADDRESS=$(grep ${NODE_NAME} /etc/hosts | head -1 | awk '{ print $1 }') && \
LOAD_BALANCER_PORT='6443' && \
LOAD_BALANCER_NAME='loadbalancer' && \
CONTROL_PLANE_ENDPOINT="${LOAD_BALANCER_NAME}:${LOAD_BALANCER_PORT}" && \
CONTROL_PLANE_ENDPOINT_TEST=$(curl -Is ${LOAD_BALANCER_NAME}:${LOAD_BALANCER_PORT} &> /dev/null && echo "OK" || echo "FAIL") && \
clear && \
echo "" && \
echo "NODE_NAME....................: ${NODE_NAME}" && \
echo "LOCAL_IP_ADDRESS.............: ${LOCAL_IP_ADDRESS}" && \
echo "CONTROL_PLANE_ENDPOINT.......: ${CONTROL_PLANE_ENDPOINT} [${CONTROL_PLANE_ENDPOINT_TEST}]" && \
echo "TOKEN........................: ${KUBEADM_TOKEN}" && \
echo "DISCOVERY_TOKEN_CA_CERT_HASH.: ${KUBEADM_DISCOVERY_TOKEN_CA_CERT_HASH}" && \
echo ""

sudo kubeadm join "${CONTROL_PLANE_ENDPOINT?}" \
  --v 1 \
  --control-plane \
  --node-name "${NODE_NAME?}" \
  --apiserver-advertise-address "${LOCAL_IP_ADDRESS?}" \
  --token "${KUBEADM_TOKEN?}" \
  --discovery-token-ca-cert-hash "${KUBEADM_DISCOVERY_TOKEN_CA_CERT_HASH?}" \
  --certificate-key "${KUBEADM_CERTIFICATE_KEY?}" && \
./watch-for-interfaces-and-routes.sh
