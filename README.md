Pre-req's 

Minikube installed

Minikube will need to be run with this command at a minimum:
```
minikube start --cpus=6 --memory=12g
```
But if you have the resouces run it this way:
```
minikube start --cpus=8 --memory=16g
```
You may also consider increaseing the size of disk allocated to your VM if you are running minikube with one of the VM (non-docker) drivers.
```
minikube start --cpus=8 --memory=16g --disk-size=100GB
```

Helm installed

You need to add the following Helm repositores:
```
helm repo add bitnami https://charts.bitnami.com/bitnami
```
```
helm repo add lensesio https://helm.repo.lenses.io/
```
Then run the following command:
```
helm repo update
```

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
Next we need to install the Confluent Schema registry.
```
helm install my-schema-registry bitnami/schema-registry -f https://raw.githubusercontent.com/lensesio-workshops/community-edition-minikube/refs/heads/main/bitnami-kafka/schema-values.yaml -n kafka
```
10. Next up you will need to install the Lenses Agent. Before we can do that we need to obtain the Agent Key from Lenses HQ. As long as your port forward is still running you can login to HQ at http://127.0.0.1:8080 - user name: admin and password: admin.

This procedure is explained in Lenses Docs: https://docs.lenses.io/latest/deployment/installation/helm/agent#configure-hq-connection-agent-key

From Lenses HQ Environment's page click on the New Environment buttom. Fill out the form and then click Create Environment. Then Lenses will generate an Agent Key for you to use. Copy the key you will need to put it into the lenses-agent-values.yaml file located here: https://github.com/lensesio-workshops/community-edition-minikube/blob/main/LensesAgent/lenses-agent-values.yaml
You should download a copy of that file and insert your agent key into it. Look for this part of the file:
```
hq:
    agentKey:
      secret:
        type: "createNew"
        name: "agentKey"
        value: "agent_key_PLEASE INSERT YOUR AGENT KEY HERE"
```
Once you have updated the values.yaml file it should look something like this:
```
hq:
    agentKey:
      secret:
        type: "createNew"
        name: "agentKey"
        value: "agent_key_cHkT0iveoPP6cGTo_uL8C9IEV33SfayNL8VyobkswkwuVnb9C"
```
But with your agent key. Once you have updated and saved your lenses-agent-values.yaml file you can apply the chart with this command:
```
helm install lenses-agent lensesio/lenses-agent -n lenses -f ./lenses-agent-values.yaml
```
11. You can now go back to the Lenses HQ UI and now you should see your cluster.
12. You may need to manually add your Schema Registry through the UI. If you do, the URL is ```http://my-schema-registry.kafka.svc.cluster.local:8081``` No auth.
13. Now you can add data and topics to your heart's content. You can create SQL processors - they will run in your lenses namespace inside your cluster.
14. If you have questions please email drew.oetzel.ext@lenses.io and I can hop on a call. 
