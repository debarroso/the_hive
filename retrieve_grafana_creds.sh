#!/bin/zsh
# This script retrieves the Grafana admin password from the manually created secret.
kubectl get secret prometheus-grafana-admin -n monitoring -o jsonpath="{.data['admin-password']}" | base64 --decode
