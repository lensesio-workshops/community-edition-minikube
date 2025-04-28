Pre-req's 

Minikube installed
Helm installed
Ability to run a shell script

*Install and configure postgres*

1. create namespace for postgres
```
kubectl create namespace postgres-system
```
2. Create PVC claim for postgres
```
kubectl apply -f https://github.com/lensesio-workshops/community-edition-minikube/blob/main/postgres-setup/minikube-pvc-setup.yaml
3. 
