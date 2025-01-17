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
  --v 0 \
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
watch -n 3 'kubectl get nodes,ds,pods,services -o wide -A'

# (Another Terminal) Watch Interfaces and Route information
./watch-for-interfaces-and-routes.sh

# Install CNI Plugin
# kubectl apply -f "https://projectcalico.docs.tigera.io/manifests/calico.yaml"
kubectl apply -f "https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml"

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
export KUBEADM_TOKEN=prku4u.kunjtmjdpetovdib
export KUBEADM_DISCOVERY_TOKEN_CA_CERT_HASH=sha256:e779e5e854e37ced47e617493235d65ab982226dccd05cb7aaa439f2f6e2c9fb
export KUBEADM_CERTIFICATE_KEY=ff359629abf2431c09b6d35fd9cd34ff81de9adce92d5583e8aa836d965d2ebd
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
  --v 0 \
  --control-plane \
  --node-name "${NODE_NAME?}" \
  --apiserver-advertise-address "${LOCAL_IP_ADDRESS?}" \
  --token "${KUBEADM_TOKEN?}" \
  --discovery-token-ca-cert-hash "${KUBEADM_DISCOVERY_TOKEN_CA_CERT_HASH?}" \
  --certificate-key "${KUBEADM_CERTIFICATE_KEY?}" && \
./watch-for-interfaces-and-routes.sh
