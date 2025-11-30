# Kind Addons

## Enable Nvidia GPU support
[Nvidia toolkit setup](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)

#### Install NVIDIA container toolkit on Arch

```shell
sudo pacman -S nvidia-container-toolkit
```

#### Configure NVIDIA  integration with docker

```shell
sudo nvidia-ctk runtime configure --runtime=docker --set-as-default

sudo systemctl daemon-reload

sudo systemctl restart docker

sudo sed -i '/accept-nvidia-visible-devices-as-volume-mounts/c\accept-nvidia-visible-devices-as-volume-mounts = true' /etc/nvidia-container-runtime/config.toml

```

#### Install Nvidia GPU operator

```shell
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia || true
helm repo update
helm install --wait --generate-name \
     -n gpu-operator --create-namespace \
     nvidia/gpu-operator --set driver.enabled=false
```

## Enable AMD GPU support

#### Install cert-manager (required by amd-gpu-operator)
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
                    --namespace cert-manager \
                    --create-namespace \
                    --version v1.15.1 \
                    --set crds.enabled=true

#### Install amd-gpu-operator
helm repo add rocm https://rocm.github.io/gpu-operator
helm repo update
helm install amd-gpu-operator rocm/gpu-operator-charts \
        --namespace kube-amd-gpu --create-namespace \
        --version=v1.3.0



## Ingress NGINX
```shell
kubectl apply -f ingress-controler.yaml

```