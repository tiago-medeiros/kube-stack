# Zabbix

# Deploy using helm
helm repo add zabbix-community https://zabbix-community.github.io/helm-zabbix
helm repo update
helm upgrade --install zabbix zabbix-community/zabbix \                                                            󱃾 kind-kubecraft 16:51:19
 --dependency-update \
 --create-namespace --namespace zabbix