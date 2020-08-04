#!/bin/bash
export MINIKUBE_IN_STYLE=false
minikube start \
  --kubernetes-version v1.17.7 \
  --driver=docker \
  --network-plugin=cni

kubectl config use-context minikube

kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml  

kubectl config use-context minikube

kubectl create namespace argocd

TOTAL_ATTEMPTS=90

clear && \
for ((i=1; i <= ${TOTAL_ATTEMPTS}; i++)); do
  NOT_READY_DEPLOYMENTS=$(kubectl -n kube-system get deploy | grep -e "0/[1-9]" | wc -l)
  
  if [ "${NOT_READY_DEPLOYMENTS:-0}" -eq "0" ]; then
    echo "All Deployments are ready!"
    break
  else
    printf "[Minikube] There are %s PODs not ready [Attempt #%i/%i]\r" ${NOT_READY_DEPLOYMENTS} ${i} ${TOTAL_ATTEMPTS}
    sleep 5
  fi
done

kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

if ! which argocd &> /dev/null; then
  echo "Need to download and install argocd CLI..."

  VERSION=$(curl --silent "https://api.github.com/repos/argoproj/argo-cd/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')

  echo "Downloading version: ${VERSION}"

  sudo curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/${VERSION}/argocd-linux-amd64

  sudo chmod +x /usr/local/bin/argocd
fi

clear && \
for ((i=1; i <= ${TOTAL_ATTEMPTS}; i++)); do
  NOT_READY_DEPLOYMENTS=$(kubectl -n argocd get deploy | grep -e "0/[1-9]" | wc -l)
  
  if [ "${NOT_READY_DEPLOYMENTS:-0}" -eq "0" ]; then
    echo "All Deployments are ready!"
    break
  else
    printf "[Argo CD] There are %s PODs not ready [Attempt #%i/%i]\r" ${NOT_READY_DEPLOYMENTS} ${i} ${TOTAL_ATTEMPTS}
    sleep 5
  fi
done

kubectl apply -n argocd -f argocd-server-service.yaml

ARGOCD_INITIAL_PASSWORD=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o name | cut -d '/' -f 2)
ARGOCD_URL=$(minikube service argocd-server -n argocd --url | grep 32443 | sed "s/http:\/\///")

clear && \
echo "ARGOCD_URL...............: ${ARGOCD_URL}" && \
echo "ARGOCD_INITIAL_PASSWORD..: ${ARGOCD_INITIAL_PASSWORD}"

argocd login \
  ${ARGOCD_URL} \
  --username admin \
  --password "${ARGOCD_INITIAL_PASSWORD}" \
  --insecure

argocd account update-password \
  --account admin \
  --current-password "${ARGOCD_INITIAL_PASSWORD}" \
  --new-password "anystrongpassword"

kubectl create ns dev

argocd app create nginx \
  --repo https://github.com/smsilva/argocd.git \
  --path nginx \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace dev

argocd app list

argocd app get nginx

argocd app sync nginx

argocd app set nginx --sync-policy automated
argocd app set nginx --auto-prune
argocd app set nginx --self-heal

clear && \
for ((i=1; i <= ${TOTAL_ATTEMPTS}; i++)); do
  NOT_READY_DEPLOYMENTS=$(kubectl -n dev get deploy | grep -e "0/[1-9]" | wc -l)
  
  if [ "${NOT_READY_DEPLOYMENTS:-0}" -eq "0" ]; then
    echo "All Deployments are ready!"
    break
  else
    printf "[NGINX Sample Project] There are %s PODs not ready [Attempt #%i/%i]\r" ${NOT_READY_DEPLOYMENTS} ${i} ${TOTAL_ATTEMPTS}
    sleep 5
  fi
done

curl $(minikube service nginx -n dev --url) -Is | head -2
