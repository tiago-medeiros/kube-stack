# Kind Addons

## Enable Nvidia GPU support
[Nvidia toolkit setup](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)

#### Install NVIDIA container toolkit on Arch

```shell
sudo pacman -S nvidia-container-toolkit
```

#### Configure NVIDIA
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

#### Ingress NGINX
```shell
kubectl apply -f ingress-controler.yaml

```

## Enable AMD GPU support