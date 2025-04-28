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
```
3. Install postgres with the Bitnami Helm chart.
```
helm install postgres bitnami/postgresql \
  --namespace postgres-system \
  --values https://raw.githubusercontent.com/lensesio-workshops/community-edition-minikube/refs/heads/main/postgres-setup/postgres-values.yaml
```
4. Create the HQ and Lenses Agent databases in postgres
```
kubectl apply -f https://raw.githubusercontent.com/lensesio-workshops/community-edition-minikube/refs/heads/main/postgres-setup/lenses-db-init-job.yaml
```
5. 
