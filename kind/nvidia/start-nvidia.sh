#!/bin/bash
set -euo pipefail
CLUSTER_NAME="kube-stack-nvidia"
CPU_ALLOC="12"
MEM_ALLOC="24Gi"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "🚀 Provisionando cluster Kubernetes com suporte a GPU NVIDIA..."
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

# Verificar dispositivos NVIDIA GPU no host
if ! ls /dev/nvidia* &>/dev/null 2>&1 || ! command -v nvidia-smi &>/dev/null; then
    echo "⚠️  ATENÇÃO: Dispositivos NVIDIA GPU não detectados (/dev/nvidia* ausentes ou nvidia-smi não encontrado)"
    echo "   Certifique-se de que:"
    echo "   - Drivers NVIDIA estão instalados no host (versão >= 470)"
    echo "   - NVIDIA Container Toolkit está instalado e configurado"
    echo "   - Serviço nvidia-persistenced está rodando (recomendado)"
    echo "   - Usuário tem permissão para acessar /dev/nvidia*"
    read -p "Deseja continuar mesmo assim? (s/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        exit 1
    fi
else
    echo "✅ GPU NVIDIA detectada no host:"
    nvidia-smi --query-gpu=name,driver_version --format=csv -i 0
fi



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
rm -f kind-config-nvidia.yaml
echo "✅ Cluster criado com sucesso!"
kubectl get nodes -o wide

# ========================================
# 4. Configuração pós-criação
# ========================================
echo "🔧 Configurando cluster..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s
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
# 6. Instalação do NVIDIA GPU Operator
# ========================================
echo "🎮 Instalando NVIDIA GPU Operator v24.9.0..."
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia --force-update
helm repo update

# Valores customizados para ambiente Kind (desabilita componentes que requerem kernel modules)

helm upgrade --install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --version v24.9.0 \
  -f gpu-operator-values.yaml \
  --wait --timeout 600s
echo "✅ NVIDIA GPU Operator instalado!"
kubectl get pods -n gpu-operator

# ========================================
# 7. Validação final
# ========================================
echo ""
echo "🔍 Validando configuração da GPU..."
sleep 15  # Aguardar operador estabilizar

# Verificar se nodes foram marcados com labels NVIDIA
if kubectl get nodes -l gpu.vendor=nvidia -o jsonpath='{.items[*].metadata.name}' | grep -q .; then
    echo "✅ Nodes com label 'gpu.vendor=nvidia' detectados:"
    kubectl get nodes -l gpu.vendor=nvidia -o wide
    
    # Verificar se recursos NVIDIA estão disponíveis
    echo ""
    echo "📊 Capacidade de GPU nos nodes:"
    kubectl get nodes -l gpu.vendor=nvidia -o jsonpath='{range .items[*]}{.metadata.name}{"\n  "}{"  nvidia.com/gpu: "}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}'
    
    echo ""
    echo "ℹ️  Para testar a GPU, execute:"
    echo "   kubectl create -f - <<EOF"
    echo "   apiVersion: v1"
    echo "   kind: Pod"
    echo "   metadata:"
    echo "     name: nvidia-gpu-test"
    echo "   spec:"
    echo "     restartPolicy: OnFailure"
    echo "     containers:"
    echo "     - name: cuda-container"
    echo "       image: nvcr.io/nvidia/cuda:12.4.0-base-ubuntu22.04"
    echo "       command: [\"nvidia-smi\"]"
    echo "       resources:"
    echo "         limits:"
    echo "           nvidia.com/gpu: 1"
    echo "     nodeSelector:"
    echo "       gpu.vendor: nvidia"
    echo "   EOF"
    echo ""
    echo "   Verifique o resultado com:"
    echo "   kubectl logs nvidia-gpu-test"
else
    echo "⚠️  Nenhum node com GPU detectado. Verifique:"
    echo "   - Drivers NVIDIA instalados no host (nvidia-smi deve funcionar)"
    echo "   - Permissões em /dev/nvidia*"
    echo "   - Status do operador: kubectl get pods -n gpu-operator"
    echo "   - Logs do device-plugin: kubectl logs -n gpu-operator -l app=nvidia-device-plugin-daemonset"
fi

echo ""
echo "🎉 Cluster '${CLUSTER_NAME}' provisionado com sucesso!"
echo "   - 1 control-plane + 3 workers com GPU NVIDIA"
echo "   - Recursos alocados: ${CPU_ALLOC} threads, ${MEM_ALLOC} RAM"
echo "   - Suporte a GPU NVIDIA configurado (via NVIDIA GPU Operator v24.9.0)"
echo "   - cert-manager v1.15.1 instalado"
echo ""
echo "💡 Dica: Para múltiplas GPUs no mesmo node, ajuste os mounts em /tmp/kind-config.yaml"