#!/bin/bash
set -euxo pipefail
export HOME=/root DEBIAN_FRONTEND=noninteractive

# Prérequis noyau
swapoff -a
printf 'overlay\nbr_netfilter\n' > /etc/modules-load.d/k8s.conf
modprobe overlay
modprobe br_netfilter
printf 'net.bridge.bridge-nf-call-iptables=1\nnet.ipv4.ip_forward=1\n' > /etc/sysctl.d/k8s.conf
sysctl --system

# containerd
apt-get update
apt-get install -y containerd curl gpg ca-certificates
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd

# kubeadm, kubelet, kubectl
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/k8s.gpg
echo "deb [signed-by=/etc/apt/keyrings/k8s.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" > /etc/apt/sources.list.d/k8s.list
apt-get update
apt-get install -y kubelet kubeadm kubectl conntrack

# Cluster
kubeadm init --pod-network-cidr=10.244.0.0/16
export KUBECONFIG=/etc/kubernetes/admin.conf
mkdir -p /home/ubuntu/.kube
cp $KUBECONFIG /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube

kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# Stockage par défaut
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ArgoCD + application (déploiement depuis le repo gitops)
kubectl create namespace argocd
kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=established crd/applications.argoproj.io --timeout=120s
kubectl apply -f https://raw.githubusercontent.com/rjafallah/cabinet-medical-gitops/main/argocd/app-dev.yaml -f https://raw.githubusercontent.com/rjafallah/cabinet-medical-gitops/main/argocd/kube-prometheus-stack.yaml -f https://raw.githubusercontent.com/rjafallah/cabinet-medical-gitops/main/argocd/loki.yaml

# Interfaces web accessibles via tunnel SSH (ArgoCD : 30443, Grafana : 30300)
kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"NodePort","ports":[{"port":443,"nodePort":30443}]}}'

echo "BOOTSTRAP TERMINE"
