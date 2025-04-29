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
9. Install the demo Kafka cluster. For simplicity we are using the Bitnami Helm Chart Open Source Apache Kafka install. This will install an empty cluster that listens on the node port to make it easier to get data in from outside the cluster.

First create the namespace.
```
kubectl apply -f https://raw.githubusercontent.com/lensesio-workshops/community-edition-minikube/refs/heads/main/bitnami-kafka/bitnami-kafka-namespace.yaml
```
Then install Kafka with the Helm Chart.
```
helm install my-kafka bitnami/kafka -f https://raw.githubusercontent.com/lensesio-workshops/community-edition-minikube/refs/heads/main/bitnami-kafka/values.yaml -n kafka
```
10. Next up you will need to install the Lenses Agent. Before we can do that we need to obtain the Agent Key from Lenses HQ. As long as your port forward is still running you can login to HQ at http://127.0.0.1:8080 - user name: admin and password: admin.

This procedure is explained in Lenses Docs: https://docs.lenses.io/latest/deployment/installation/helm/agent#configure-hq-connection-agent-key

From Lenses HQ Environment's page click on the New Environment buttom. Fill out the form and then click Create Environment. Then Lenses will generate an Agent Key for you to use. 

11. 
