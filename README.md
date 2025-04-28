Pre-req's 

Minikube installed
Helm installedhttps://github.com/lensesio-workshops/community-edition-minikube/blob/main/README.md
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
5. Create lenses namespace.
```
kubectl create namespace lenses
```
6. Install Lenses HQ with Helm
```
helm install lenses-hq lensesio/lenses-hq -n lenses -f https://raw.githubusercontent.com/lensesio-workshops/community-edition-minikube/refs/heads/main/lensesHQ/lenses-hq-chart-basic.yaml
```
7. The simplest way to access the HQ UI is to setup a port forward.
```
kubectl port-forward -n lenses service/lenses-hq 8080:80
```
8. Point your web browser to http://127.0.0.1:8080. Login with user name: admin and password: admin
9. Install the demo Kafka cluster. Note this includes Apache Kafka, Kafka Connect, and Schema Registry as well as simple synthetic data generators.
```
kubectl apply -f https://raw.githubusercontent.com/lensesio-workshops/community-edition-minikube/refs/heads/main/demo-kafka/demo-kafka-namespace.yaml
```
```
kubectl apply -f https://raw.githubusercontent.com/lensesio-workshops/community-edition-minikube/refs/heads/main/demo-kafka/demo-kafka-pvc.yaml
```
```
kubectl apply -f https://raw.githubusercontent.com/lensesio-workshops/community-edition-minikube/refs/heads/main/demo-kafka/demo-kafka-deployment.yaml
```
```
kubectl apply -f https://raw.githubusercontent.com/lensesio-workshops/community-edition-minikube/refs/heads/main/demo-kafka/demo-kafka-services.yaml
```
10. 
