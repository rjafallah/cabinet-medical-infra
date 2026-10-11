# Cabinet Médical — infrastructure

Terraform crée une instance EC2 qui s'installe seule en cluster Kubernetes (kubeadm, 1 nœud), puis déploie ArgoCD, qui déploie l'application et la stack d'observabilité depuis le dépôt gitops.

Projet complet : [cabinet-medical-app](https://github.com/rjafallah/cabinet-medical-app) · [cabinet-medical-gitops](https://github.com/rjafallah/cabinet-medical-gitops).

## Ce que Terraform crée

| Ressource | Détail |
|---|---|
| `aws_key_pair` | clé publique SSH (`~/.ssh/blazing-key.pub`) |
| `aws_security_group` | SSH (22) autorisé depuis **une seule IP** ; aucun autre port entrant |
| `aws_instance` | Ubuntu 22.04, `m7i-flex.large` (8 Go de RAM), disque gp3 de 30 Go, région `eu-west-3` |

## Ce que fait `bootstrap.sh` (user_data)

1. Désactive le swap, charge `overlay` et `br_netfilter`, règle les sysctl réseau.
2. Installe containerd (`SystemdCgroup = true`).
3. Installe kubeadm, kubelet, kubectl (Kubernetes 1.31) et `conntrack`.
4. `kubeadm init --pod-network-cidr=10.244.0.0/16`, copie le kubeconfig pour l'utilisateur `ubuntu`.
5. Installe Flannel (CNI) et retire le taint `control-plane` (un seul nœud).
6. Installe `local-path-provisioner` comme StorageClass par défaut.
7. Installe Helm.
8. Installe ArgoCD, puis applique les trois `Application` du dépôt gitops (application, Prometheus/Grafana, Loki).
9. Expose ArgoCD (NodePort 30443) ; Grafana est exposé en 30300 par son chart.

Le journal d'installation se lit dans `/var/log/cloud-init-output.log` ; il se termine par `BOOTSTRAP TERMINE`.

## Utilisation

Prérequis : Terraform, AWS CLI configuré (`aws configure`), une clé SSH.

```bash
cp terraform.tfvars.example terraform.tfvars   # my_ip = "<ton IPv4>"
terraform init
terraform apply                                # ~1 min, puis 5 à 8 min pour le cluster
terraform output public_ip
ssh -i ~/.ssh/<clé> ubuntu@<IP>
```

Vérifications sur la machine :

```bash
sudo tail /var/log/cloud-init-output.log       # BOOTSTRAP TERMINE
kubectl get nodes                              # 1 nœud Ready
kubectl get applications -n argocd             # Synced / Healthy
```

Interfaces web : voir le README du dépôt gitops (tunnel SSH).

**À la fin de chaque session :**

```bash
terraform destroy
```

## Coût

Environ 0,1 $/h tant que l'instance tourne. Le cluster se recrée en une commande : le détruire entre deux sessions est le fonctionnement prévu.

## Limites

- Un seul nœud : pas de haute disponibilité.
- VPC par défaut du compte, pas de réseau dédié.
- Fichier d'état Terraform local (pas de backend distant).
- Les manifests Flannel, ArgoCD et Helm sont téléchargés depuis leurs canaux « stable » au démarrage : le résultat peut varier dans le temps.
