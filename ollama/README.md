# Ollama

Ollama experiments and notes

# Local Configuration

Add this configuration in /etc/hosts

```shell
echo "127.0.0.1 ollama.local" > /etc/hosts
``` 


# Kubernetes
Add [Ollama Helm repo](https://artifacthub.io/packages/helm/ollama-helm/ollama) 


```shell
helm repo add ollama-helm https://otwld.github.io/ollama-helm/
helm repo update
helm install -f values.yaml ollama ollama-helm/ollama --namespace ollama --create-namespace
```


# Visual Code 
An example configuration for the Continue extension on Visual Studio Code. You can add more models and change the API key to your own Ollama instance.

```json
"models": [
  {
    "model": "llama3.1",
    "apiBase": "http://ollama.localhost",
    "provider": "ollama",
    "apiKey": "",
    "title": "Llama 3.1"
  }
],
"tabAutocompleteModel": {
  "title": "Codellama",
  "apiBase": "http://ollama.localhost",
  "provider": "ollama",
  "model": "codellama",
  "apiKey": ""
},

```