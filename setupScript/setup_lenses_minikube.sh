#!/bin/bash

# Lenses.io Community Edition Minikube Setup Script
# Based on instructions from: https://github.com/lensesio-workshops/community-edition-minikube

set -e  # Exit immediately if a command exits with a non-zero status

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to display colored output
print_info() {
  echo -e "\033[1;34m[INFO]\033[0m $1"
}

print_success() {
  echo -e "\033[1;32m[SUCCESS]\033[0m $1"
}

print_error() {
  echo -e "\033[1;31m[ERROR]\033[0m $1"
}

print_warning() {
  echo -e "\033[1;33m[WARNING]\033[0m $1"
}

print_step() {
  echo -e "\n\033[1;36m[STEP $1]\033[0m $2"
}

# Check for required tools
print_info "Checking for required tools..."
REQUIRED_TOOLS=("minikube" "kubectl" "helm")
MISSING_TOOLS=()

for tool in "${REQUIRED_TOOLS[@]}"; do
  if ! command_exists "$tool"; then
    MISSING_TOOLS+=("$tool")
  fi
done

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
  print_error "The following required tools are missing: ${MISSING_TOOLS[*]}"
  print_info "Please install these tools before running this script."
  
  echo "Installation guides:"
  echo "- Minikube: https://minikube.sigs.k8s.io/docs/start/"
  echo "- Kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl/"
  echo "- Helm: https://helm.sh/docs/intro/install/"
  
  exit 1
fi

# Start Minikube with recommended resources
print_step "1" "Starting Minikube with recommended resources"

# Prompt user for resource allocation
echo "Choose Minikube resource allocation:"
echo "1) Minimum resources: 6 CPUs, 12GB memory"
echo "2) Recommended resources: 8 CPUs, 16GB memory"
echo "3) Recommended resources with increased disk: 8 CPUs, 16GB memory, 100GB disk"
read -p "Enter your choice (1-3): " resource_choice

case $resource_choice in
  1)
    print_info "Starting Minikube with minimum resources"
    minikube start --cpus=6 --memory=12g
    ;;
  2)
    print_info "Starting Minikube with recommended resources"
    minikube start --cpus=8 --memory=16g
    ;;
  3)
    print_info "Starting Minikube with recommended resources and increased disk"
    minikube start --cpus=8 --memory=16g --disk-size=100GB
    ;;
  *)
    print_warning "Invalid choice, starting with minimum resources"
    minikube start --cpus=6 --memory=12g
    ;;
esac

# Add Helm repositories
print_step "2" "Adding Helm repositories"
print_info "Adding Bitnami and Lensesio Helm repositories"
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add lensesio https://helm.repo.lenses.io/
helm repo update

# Install and configure PostgreSQL
print_step "3" "Installing and configuring PostgreSQL"
print_info "Creating namespace for PostgreSQL"
kubectl create namespace postgres-system

print_info "Creating PVC claim for PostgreSQL"
kubectl apply -f https://raw.githubusercontent.com/lensesio-workshops/community-edition-minikube/refs/heads/main/postgres-setup/postgres-pvc.yaml

print_info "Installing PostgreSQL with Bitnami Helm chart"
helm install postgres bitnami/postgresql \
  --namespace postgres-system \
  --values https://raw.githubusercontent.com/lensesio-workshops/community-edition-minikube/refs/heads/main/postgres-setup/postgres-values.yaml

print_info "Creating the HQ and Lenses Agent databases in PostgreSQL"
kubectl apply -f https://raw.githubusercontent.com/lensesio-workshops/community-edition-minikube/refs/heads/main/postgres-setup/lenses-db-init-job.yaml

print_info "Waiting for PostgreSQL init job to start"
sleep 5

# Check for job completion in a more resilient way
JOB_NAME=$(kubectl get jobs -n postgres-system -o custom-columns=NAME:.metadata.name | grep db-init | tail -n 1)

if [ -n "$JOB_NAME" ]; then
  print_info "Found database init job: $JOB_NAME"
  
  # Check if job is already completed
  JOB_STATUS=$(kubectl get job $JOB_NAME -n postgres-system -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')
  
  if [ "$JOB_STATUS" == "True" ]; then
    print_success "Database init job completed successfully"
  else
    print_info "Waiting for database init job to complete (max 60 seconds)"
    
    # Loop with timeout to check job status
    TIMEOUT=60
    start_time=$(date +%s)
    
    while true; do
      JOB_STATUS=$(kubectl get job $JOB_NAME -n postgres-system -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "")
      
      if [ "$JOB_STATUS" == "True" ]; then
        print_success "Database init job completed successfully"
        break
      fi
      
      current_time=$(date +%s)
      elapsed=$((current_time - start_time))
      
      if [ $elapsed -ge $TIMEOUT ]; then
        print_warning "Timeout waiting for database init job to complete. Continuing anyway."
        break
      fi
      
      print_info "Job still running. Waiting 5 more seconds..."
      sleep 5
    done
  fi
else
  print_warning "Could not find database init job. It may have completed already or has a different name."
  sleep 10  # Small wait to ensure database operations have time to complete
fi

# Install and Connect to Lenses HQ
print_step "4" "Installing Lenses HQ"
print_info "Creating namespace for Lenses"
kubectl create namespace lenses

print_info "Installing Lenses HQ with Helm"
helm install lenses-hq lensesio/lenses-hq -n lenses -f https://raw.githubusercontent.com/lensesio-workshops/community-edition-minikube/refs/heads/main/lensesHQ/lenses-hq-chart-basic.yaml

print_info "Waiting for Lenses HQ to be ready"
kubectl rollout status deployment/lenses-hq -n lenses --timeout=300s

# Install Apache Kafka and Schema Registry
print_step "5" "Installing Apache Kafka and Schema Registry"
print_info "Creating namespace for Kafka"
kubectl apply -f https://raw.githubusercontent.com/lensesio-workshops/community-edition-minikube/refs/heads/main/bitnami-kafka/bitnami-kafka-namespace.yaml

print_info "Installing Kafka with Bitnami Helm chart"
helm install my-kafka bitnami/kafka -f https://raw.githubusercontent.com/lensesio-workshops/community-edition-minikube/refs/heads/main/bitnami-kafka/values.yaml -n kafka

print_info "Waiting for Kafka to be ready"
print_info "Waiting for Kafka controller pods to be created"
sleep 20  # Give more time for pods to be created

# Check if controller pods exist, if not, try different label patterns
CONTROLLER_PODS=$(kubectl get pods -n kafka -l app.kubernetes.io/instance=my-kafka -o name 2>/dev/null || true)

if [ -z "$CONTROLLER_PODS" ]; then
  print_info "Trying different pod naming pattern..."
  CONTROLLER_PODS=$(kubectl get pods -n kafka | grep my-kafka | grep controller | awk '{print $1}')
fi

if [ -n "$CONTROLLER_PODS" ]; then
  print_info "Found Kafka pods. Waiting for them to be ready."
  for pod in $CONTROLLER_PODS; do
    print_info "Waiting for pod $pod to be ready"
    kubectl wait --for=condition=ready pod/$pod -n kafka --timeout=300s || true
  done
  
  # Extra wait time to ensure Kafka is fully initialized
  print_info "Giving Kafka extra time to fully initialize..."
  sleep 60
else
  print_warning "Could not find Kafka controller pods, waiting longer"
  sleep 90  # Wait longer to give Kafka more time to start
fi

print_info "Installing Confluent Schema Registry"
helm install my-schema-registry bitnami/schema-registry -f https://raw.githubusercontent.com/lensesio-workshops/community-edition-minikube/refs/heads/main/bitnami-kafka/schema-values.yaml -n kafka

print_info "Waiting for Schema Registry to be ready"
sleep 20  # Give time for pods to be created

# Check for the schema registry pods - they might be StatefulSet or Deployment
SCHEMA_PODS=$(kubectl get pods -n kafka -l app.kubernetes.io/name=schema-registry -o name 2>/dev/null || true)

if [ -z "$SCHEMA_PODS" ]; then
  print_info "Trying different schema registry pod pattern..."
  SCHEMA_PODS=$(kubectl get pods -n kafka | grep schema-registry | awk '{print $1}')
fi

if [ -n "$SCHEMA_PODS" ]; then
  print_info "Found Schema Registry pods. Waiting for them to be ready."
  for pod in $SCHEMA_PODS; do
    print_info "Waiting for pod $pod to be ready"
    kubectl wait --for=condition=ready pod/$pod -n kafka --timeout=300s || true
  done
else
  print_warning "Could not find Schema Registry pods, waiting a bit longer"
  sleep 60  # Give more time for schema registry to start
fi

# Setup port forwarding for accessing Lenses HQ UI
print_step "6" "Setting up access to Lenses HQ UI"
print_info "Setting up port forwarding to access Lenses HQ"
echo "To access Lenses HQ, open a new terminal and run the following command:"
echo "kubectl port-forward -n lenses service/lenses-hq 8080:80"
echo "Then visit http://127.0.0.1:8080 in your browser"
echo "Login with username: admin and password: admin"

# Install Lenses Agent
print_step "7" "Installing Lenses Agent"
print_info "To install Lenses Agent, you need to:"
cat << EOF
1. Access Lenses HQ UI at http://127.0.0.1:8080 (after setting up port forwarding)
2. Login with username: admin and password: admin
3. From the Environments page, click on "New Environment"
4. Fill out the form and click "Create Environment"
5. Copy the Agent Key that is generated
6. Download the lenses-agent-values.yaml file from:
   https://github.com/lensesio-workshops/community-edition-minikube/blob/main/LensesAgent/lenses-agent-values.yaml
7. Edit the file and replace "agent_key_PLEASE INSERT YOUR AGENT KEY HERE" with your actual agent key
8. Run the following command to install Lenses Agent:
   helm install lenses-agent lensesio/lenses-agent -n lenses -f ./lenses-agent-values.yaml

EOF

# Prompt user if they want to start port forwarding now
read -p "Do you want to start port forwarding to Lenses HQ now? (y/n): " start_portfwd

if [[ "$start_portfwd" =~ ^[Yy]$ ]]; then
  print_info "Starting port forwarding to Lenses HQ"
  print_info "Press Ctrl+C to stop port forwarding when you're done"
  sleep 2
  kubectl port-forward -n lenses service/lenses-hq 8080:80
else
  print_info "You can manually start port forwarding later with:"
  print_info "kubectl port-forward -n lenses service/lenses-hq 8080:80"
fi

print_success "Setup completed!"
print_info "Remember to add your Schema Registry through the Lenses HQ UI if needed."
print_info "The Schema Registry URL is: http://my-schema-registry.kafka.svc.cluster.local:8081 (No auth)"
print_info "For questions, please email: drew.oetzel.ext@lenses.io"
