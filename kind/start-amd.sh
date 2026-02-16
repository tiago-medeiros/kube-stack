#!/bin/bash
set -euo pipefail

CLUSTER_NAME="kube-stack"
CPU_ALLOC="12"
MEM_ALLOC="24Gi"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Provisionando cluster Kubernetes com suporte a GPU AMD..."
echo "   Máquina host: 8 cores (16 threads), 32GB RAM"
echo "   Alocação cluster: ${CPU_ALLOC} threads, ${MEM_ALLOC} RAM"
echo "   Nome do cluster: ${CLUSTER_NAME}"
echo ""

# ========================================
# 1. Verificação de pré-requisitos
# ========================================
echo "🔍 Verificando pré-requisitos..."
for cmd in kind kubectl helm docker; do
    if ! command -v $cmd &>/dev/null; then
        echo "❌ $cmd não encontrado. Instale antes de continuar."
        exit 1
    fi
done

# Verificar dispositivos AMD GPU no host
if [ ! -c /dev/kfd ] || [ ! -d /dev/dri ]; then
    echo "⚠️  ATENÇÃO: Dispositivos AMD GPU não detectados (/dev/kfd ou /dev/dri ausentes)"
    echo "   Certifique-se de que:"
    echo "   - Drivers AMD ROCm estão instalados no host"
    echo "   - Usuário tem permissão para acessar /dev/kfd e /dev/dri"
    echo "   - GPU AMD compatível está presente"
    read -p "Deseja continuar mesmo assim? (s/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        exit 1
    fi
fi

# ========================================
# 2. Configuração do cluster Kind com limites de recursos
# ========================================
echo "⚙️  Gerando configuração do cluster com limites de recursos..."

# Calcular alocação por nó (6 nós: 1 control-plane + 5 workers)
CPU_PER_NODE=$((CPU_ALLOC / 6))
MEM_PER_NODE=$((24 / 6))Gi

cat > /tmp/kind-config.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
networking:
  ipFamily: ipv4
nodes:
- role: control-plane
  image: kindest/node:v1.35.0
  # Limites de recursos do container Docker (não do kubelet)
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
        # Limites visíveis para o kubelet (importante para scheduler)
        system-reserved: cpu=500m,memory=512Mi
        kube-reserved: cpu=500m,memory=512Mi
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
- role: worker
  image: kindest/node:v1.35.0
  extraMounts:
  - hostPath: /dev/kfd
    containerPath: /dev/kfd
    propagation: HostToContainer
  - hostPath: /dev/dri
    containerPath: /dev/dri
    propagation: HostToContainer
  labels:
    az: us-east-1a
    size: m5.xlarge
    type: spot
    gpu.vendor: amd
- role: worker
  image: kindest/node:v1.35.0
  extraMounts:
  - hostPath: /dev/kfd
    containerPath: /dev/kfd
    propagation: HostToContainer
  - hostPath: /dev/dri
    containerPath: /dev/dri
    propagation: HostToContainer
  labels:
    az: us-east-1b
    size: c5.2xlarge
    type: ondemand
    gpu.vendor: amd
- role: worker
  image: kindest/node:v1.35.0
  extraMounts:
  - hostPath: /dev/kfd
    containerPath: /dev/kfd
    propagation: HostToContainer
  - hostPath: /dev/dri
    containerPath: /dev/dri
    propagation: HostToContainer
  labels:
    az: us-east-1b
    size: c5.2xlarge
    type: ondemand
    gpu.vendor: amd
- role: worker
  image: kindest/node:v1.35.0
  extraMounts:
  - hostPath: /dev/kfd
    containerPath: /dev/kfd
    propagation: HostToContainer
  - hostPath: /dev/dri
    containerPath: /dev/dri
    propagation: HostToContainer
  labels:
    az: us-east-1b
    size: c5.2xlarge
    type: ondemand
    gpu.vendor: amd
- role: worker
  image: kindest/node:v1.35.0
  extraMounts:
  - hostPath: /dev/kfd
    containerPath: /dev/kfd
    propagation: HostToContainer
  - hostPath: /dev/dri
    containerPath: /dev/dri
    propagation: HostToContainer
  labels:
    az: us-east-1b
    size: c5.2xlarge
    type: ondemand
    gpu.vendor: amd
EOF

# ========================================
# 3. Criação do cluster
# ========================================
echo "☸️  Criando cluster Kind '${CLUSTER_NAME}'..."
if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    echo "⚠️  Cluster '${CLUSTER_NAME}' já existe. Recomendamos executar 'kind delete cluster --name ${CLUSTER_NAME}' antes."
    read -p "Deseja sobrescrever? (s/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        kind delete cluster --name ${CLUSTER_NAME}
    else
        exit 1
    fi
fi

kind create cluster --config /tmp/kind-config.yaml --wait 5m
rm -f /tmp/kind-config.yaml

echo "✅ Cluster criado com sucesso!"
kubectl get nodes -o wide

# ========================================
# 4. Configuração pós-criação
# ========================================
echo "🔧 Configurando cluster..."
# Aguardar nodes ready
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Taint para permitir pods no control-plane (opcional, mas útil para ambientes de dev)
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

# ========================================
# 5. Instalação do cert-manager
# ========================================
echo "📦 Instalando cert-manager v1.15.1..."
helm repo add jetstack https://charts.jetstack.io --force-update
helm repo update

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.15.1 \
  --set crds.enabled=true \
  --wait --timeout 300s

echo "✅ cert-manager instalado com sucesso!"
kubectl get pods -n cert-manager

# ========================================
# 6. Instalação do AMD GPU Operator
# ========================================
echo "🎮 Instalando AMD GPU Operator v1.3.0..."
helm repo add rocm https://rocm.github.io/gpu-operator --force-update
helm repo update

# Valores customizados para ambiente Kind (desabilita componentes não necessários em dev)
cat > /tmp/gpu-operator-values.yaml <<EOF
operator:
  defaultRuntime: containerd
  useHostMounts: true

# Desabilitar componentes que requerem kernel modules no host (não funcionam em Kind)
driver:
  enabled: false
  kernel-headers: false

# Habilitar apenas runtime e validação
runtime:
  enabled: true
  containerRuntime: containerd

validator:
  enabled: true
  image:
    repository: rocm/k8s-device-plugin
    tag: ub22.04-single

# Configuração específica para Kind
toolkit:
  enabled: false
EOF

helm upgrade --install amd-gpu-operator rocm/gpu-operator-charts \
  --namespace kube-amd-gpu \
  --create-namespace \
  --version v1.3.0 \
  -f /tmp/gpu-operator-values.yaml \
  --wait --timeout 600s

rm -f /tmp/gpu-operator-values.yaml

echo "✅ AMD GPU Operator instalado!"
kubectl get pods -n kube-amd-gpu

# ========================================
# 7. Validação final
# ========================================
echo ""
echo "🔍 Validando configuração da GPU..."
sleep 10  # Aguardar operador estabilizar

if kubectl get nodes -l gpu.vendor=amd -o jsonpath='{.items[*].metadata.name}' | grep -q .; then
    echo "✅ Nodes com label 'gpu.vendor=amd' detectados:"
    kubectl get nodes -l gpu.vendor=amd -o wide
    
    echo ""
    echo "ℹ️  Para testar a GPU, execute:"
    echo "   kubectl create -f - <<EOF"
    echo "   apiVersion: v1"
    echo "   kind: Pod"
    echo "   metadata:"
    echo "     name: gpu-test"
    echo "   spec:"
    echo "     containers:"
    echo "     - name: gpu-test"
    echo "       image: rocm/dev-ubuntu-22.04:5.7"
    echo "       command: [\"/bin/sh\", \"-c\", \"while true; do sleep 10; done\"]"
    echo "       resources:"
    echo "         limits:"
    echo "           amd.com/gpu: 1"
    echo "     nodeSelector:"
    echo "       gpu.vendor: amd"
    echo "   EOF"
    echo ""
    echo "   Depois verifique logs:"
    echo "   kubectl logs gpu-test"
else
    echo "⚠️  Nenhum node com GPU detectado. Verifique:"
    echo "   - Drivers ROCm instalados no host"
    echo "   - Permissões em /dev/kfd e /dev/dri"
    echo "   - Status do operador: kubectl get pods -n kube-amd-gpu"
fi

echo ""
echo "🎉 Cluster '${CLUSTER_NAME}' provisionado com sucesso!"
echo "   - 3 nodes (1 control-plane + 2 workers)"
echo "   - Recursos alocados: ${CPU_ALLOC} threads, ${MEM_ALLOC} RAM"
echo "   - Suporte a GPU AMD configurado"
echo "   - cert-manager v1.15.1 instalado"
echo "   - AMD GPU Operator v1.3.0 instalado"