# Installing Control Plane on the First Control Plane Node only (master-1)
LOCAL_IP_ADDRESS=$(grep $(hostname -s) /etc/hosts | awk '{ print $1 }')
NETWORK_INTERFACE_NAME=$(ip addr show | grep ${LOCAL_IP_ADDRESS} | awk '{ print $7 }')
LOAD_BALANCER_PORT='6443'
LOAD_BALANCER_DNS='lb'

echo "" && \
echo "NETWORK_INTERFACE_NAME.....: ${NETWORK_INTERFACE_NAME}" && \
echo "LOCAL_IP_ADDRESS...........: ${LOCAL_IP_ADDRESS}" && \
echo "ADVERTISE_ADDRESS..........: ${LOAD_BALANCER_DNS}:${LOAD_BALANCER_PORT}" && \
echo "KUBERNETES_BASE_VERSION....: ${KUBERNETES_BASE_VERSION}" && \
echo ""

# Initialize master-1 (Take note of the two Join commands)
SECONDS=0

NODE_NAME=$(hostname -s) && \
sudo kubeadm init \
  --node-name "${NODE_NAME}" \
  --apiserver-advertise-address "${LOCAL_IP_ADDRESS}" \
  --kubernetes-version "${KUBERNETES_BASE_VERSION}" \
  --control-plane-endpoint "${LOAD_BALANCER_DNS}:${LOAD_BALANCER_PORT}" \
  --upload-certs

printf '%d hour %d minute %d seconds\n' $((${SECONDS}/3600)) $((${SECONDS}%3600/60)) $((${SECONDS}%60))

# Copy token information like those 3 lines below and paste at the end of this file and into 3-worker-nodes.sh file. 
  --token u32c89.1p22tpar81a64oip \
  --discovery-token-ca-cert-hash sha256:6a4667711975b74b7dec401c8c389b83278a28722ed5cead4e60166630938e8c \
  --certificate-key 08e64aaadd103bdcb5b8f1df3bfc24816540259ab0ae92b717af8382c4be5071

# Set Default Namespace to kube-system
kubectl config set-context --current --namespace kube-system

# Install the Weave CNI Plugin
# https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/#pod-network
CNI_ADD_ON_FILE="cni-add-on-weave.yaml" && \
wget \
  "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')" \
  --output-document "${CNI_ADD_ON_FILE}" \
  --quiet && \
kubectl apply -f "${CNI_ADD_ON_FILE}"

# Watch Nodes and Pods from kube-system namespace
watch -n 3 'kubectl get nodes,deployments,replicasets,pods,services,endpoints -o wide'

# Optional
BAT_VERSION="0.15.1" && \
BAT_DEB_FILE="bat_${BAT_VERSION}_amd64.deb" && \
wget "https://github.com/sharkdp/bat/releases/download/v${BAT_VERSION}/${BAT_DEB_FILE}" \
  --output-document "${BAT_DEB_FILE}" \
  --quiet && \
sudo dpkg -i "${BAT_DEB_FILE}" && rm "${BAT_DEB_FILE}"

echo "alias cat='bat -p'" >> ~/.bash_aliases && source ~/.bash_aliases

# Adding a Control Plane Node
LOCAL_IP_ADDRESS=$(grep $(hostname -s) /etc/hosts | head -1 | cut -d " " -f 1) && \
echo "" && \
echo "LOCAL_IP_ADDRESS...........: ${LOCAL_IP_ADDRESS}" && \
echo ""

# The parameters below are getting from the first Contol Plane Config
#   - token
#   - discovery-token-ca-cert-hash
#   - certificate-key
NODE_NAME=$(hostname -s) && \
sudo kubeadm join lb:6443 \
  --control-plane \
  --node-name "${NODE_NAME}" \
  --apiserver-advertise-address "${LOCAL_IP_ADDRESS}" \
  --token u32c89.1p22tpar81a64oip \
  --discovery-token-ca-cert-hash sha256:6a4667711975b74b7dec401c8c389b83278a28722ed5cead4e60166630938e8c \
  --certificate-key 08e64aaadd103bdcb5b8f1df3bfc24816540259ab0ae92b717af8382c4be5071

# Reset Node Config
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d && \
sudo rm -rf ${HOME}/.kube/config
