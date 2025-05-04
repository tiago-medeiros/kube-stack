# Install ArgoCD


Add the argo repo and install using helm

```shell
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo
helm install argocd argo/argo-cd -n argocd --wait --create-namespace
```

Create an ingress for Argo

```shell
kubectl apply -f ingress.yaml
```

Create an entry on /etc/hosts

```shell
echo "127.0.0.1 argocd.local" >> /etc/hosts
```

The defaul user is admin. To get the initial password use the following command

```shell
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```