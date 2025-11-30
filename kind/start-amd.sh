#!/bin/bash


# Start a kind cluster with AMD GPU support
kind create cluster --config=amd-gpu.yaml

# Creare a ingress controller
kubectl apply -f ingress-controler.yaml


# Install cert-manager and AMD GPU operator

helm install cert-manager jetstack/cert-manager \
                    --namespace cert-manager \
                    --create-namespace \
                    --version v1.15.1 \
                    --set crds.enabled=true

helm install amd-gpu-operator rocm/gpu-operator-charts \
        --namespace kube-amd-gpu --create-namespace \
        --version=v1.3.0

helm install -f ../ollama/values.yaml ollama otwld/ollama \ 
--namespace ollama --create-namespace