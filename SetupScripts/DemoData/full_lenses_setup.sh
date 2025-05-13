#!/bin/bash

# Complete Lenses.io Community Edition Setup Script with Car Insurance Demo
# Created by combining multiple script parts with exact copy of values file

# This script automates the full setup process including the insurance demo

set -e  # Exit immediately if a command exits with a non-zero status

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Functions to display colored output
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

print_instruction() {
  echo -e "\033[1;35m[INSTRUCTION]\033[0m $1"
}

# Check for required tools
print_info "Checking for required tools..."
REQUIRED_TOOLS=("minikube" "kubectl" "helm" "docker")
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
  echo "- Docker: https://docs.docker.com/get-docker/"
  
  exit 1
fi

# Create a directory for all demo files
DEMO_DIR="lenses-demo-files"
mkdir -p "$DEMO_DIR"
cd "$DEMO_DIR"


# This script should be combined with setup_part1.sh

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

# Preload container images
print_step "2" "Preloading container images to reduce waiting time"
print_info "This may take a few minutes but will save time later"

# Use eval to ensure we're using minikube's docker daemon
eval $(minikube docker-env)

# Pull necessary images
print_info "Pulling PostgreSQL image"
docker pull bitnami/postgresql:14.8.0-debian-11-r91 &

print_info "Pulling Kafka images"
docker pull bitnami/kafka:3.4.1-debian-11-r0 &
docker pull bitnami/schema-registry:7.4.0-debian-11-r21 &

print_info "Pulling Lenses images"
docker pull lensesio/lenses-hq:6.0.0 &
docker pull lensesio/lenses-agent:6.0.0 &

# Wait for all background pulls to complete
wait
print_success "All images preloaded successfully!"

# Add Helm repositories
print_step "3" "Adding Helm repositories"
print_info "Adding Bitnami and Lensesio Helm repositories"
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add lensesio https://helm.repo.lenses.io/
helm repo update

# Install and configure PostgreSQL
print_step "4" "Installing and configuring PostgreSQL"
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
print_step "5" "Installing Lenses HQ"
print_info "Creating namespace for Lenses"
kubectl create namespace lenses

print_info "Installing Lenses HQ with Helm"
helm install lenses-hq lensesio/lenses-hq -n lenses -f https://raw.githubusercontent.com/lensesio-workshops/community-edition-minikube/refs/heads/main/lensesHQ/lenses-hq-chart-basic.yaml

print_info "Waiting for Lenses HQ to be ready"
kubectl rollout status deployment/lenses-hq -n lenses --timeout=300s

# Install Apache Kafka and Schema Registry
print_step "6" "Installing Apache Kafka and Schema Registry"
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
# Only replaces the agent key in the exact same format

# Setup port forwarding instruction for accessing Lenses HQ UI
print_step "7" "Setting up access to Lenses HQ UI"
print_instruction "IMPORTANT: Open a NEW terminal window and run the following command:"
echo "kubectl port-forward -n lenses service/lenses-hq 8080:80"
print_instruction "Then visit http://127.0.0.1:8080 in your browser"
print_instruction "Login with username: admin and password: admin"
print_instruction "LEAVE THIS PORT-FORWARD RUNNING while continuing with the setup in this terminal"

# Prompt user to confirm port-forwarding is running
read -p "Have you opened a new terminal and started the port-forward command? (y/n): " port_forward_running

if [[ "$port_forward_running" != "y" && "$port_forward_running" != "Y" ]]; then
  print_warning "Please open a new terminal and run the port-forward command before continuing."
  print_instruction "Run this command in the new terminal: kubectl port-forward -n lenses service/lenses-hq 8080:80"
  read -p "Press Enter once you've started the port-forward in another terminal: " confirm
fi

# Extract and prepare agent values template file - EXACT COPY from your existing file
cat > lenses-agent-values.yaml << 'EOF'
image:
  repository: lensesio/lenses-agent
  tag: 6.0.0
  pullPolicy: IfNotPresent
lensesAgent:
  # Postgres connection
  storage:
    postgres:
      enabled: true
      host: postgres-postgresql.postgres-system.svc.cluster.local
      port: 5432
      username: lenses_agent
      password: changeme
      database: lenses_agent
  hq:
    agentKey:
      secret:
        type: "createNew"
        name: "agentKey"
        value: "AGENT_KEY_PLACEHOLDER"
  sql:
        processorImage: hub.docker.com/r/lensesioextra/sql-processor/
        processorImageTag: latest
        mode: KUBERNETES
        heap: 1024M
        minHeap: 128M
        memLimit: 1152M
        memRequest: 128M
        livenessInitialDelay: 60 seconds
        namespace: lenses
  provision:
    path: /mnt/provision-secrets
    connections:
      lensesHq:
        - name: lenses-hq
          version: 1
          tags: ['hq']
          configuration:
            server:
              value: lenses-hq.lenses.svc.cluster.local
            port:
              value: 10000
            agentKey:
              value: ${LENSESHQ_AGENT_KEY}
      kafka:
        # There can only be one Kafka cluster at a time
        - name: kafka
          version: 1
          tags: ['staging', 'pseudo-data-only']
          configuration:
            kafkaBootstrapServers:
              value:
                - PLAINTEXT://my-kafka.kafka.svc.cluster.local:9092
            protocol:
              value: PLAINTEXT
      confluentSchemaRegistry:
        # There can only be one schema registry at a time
        - name: schema-registry
          version: 1
          tags: ['staging']
          configuration:
            schemaRegistryUrls:
              value:
                - http://my-schema-registry.kafka.svc.cluster.local:8081
EOF

# Guide user to get agent key and install agent
print_step "8" "Getting Agent Key from Lenses HQ"
print_instruction "Follow these steps in the Lenses HQ web interface:"
echo "1. After logging into Lenses HQ at http://127.0.0.1:8080"
echo "2. Click on 'Environments' in the left navigation menu"
echo "3. Click on the 'New Environment' button"
echo "4. Enter a name for your environment (e.g., 'Minikube Demo')"
echo "5. Click 'Create Environment'"
echo "6. Copy the displayed Agent Key"

# Prompt for the agent key
read -p "Paste the Agent Key here: " agent_key

# Replace agent key in template while preserving quotes
if [ -n "$agent_key" ]; then
  # Use perl for a more reliable replacement that preserves quotes and handles special characters
  perl -i -pe "s/\"AGENT_KEY_PLACEHOLDER\"/\"$agent_key\"/g" lenses-agent-values.yaml
  print_info "Agent key has been set in the configuration file"
else
  print_error "No agent key provided. Using placeholder value."
fi

# Install Lenses Agent
print_step "9" "Installing Lenses Agent"
print_info "Installing Lenses Agent with Helm"
# Try uninstalling first in case there was a previous failed attempt
helm uninstall lenses-agent -n lenses 2>/dev/null || true
sleep 5

# Now install with the values file
helm install lenses-agent lensesio/lenses-agent -n lenses -f ./lenses-agent-values.yaml

print_info "Waiting for Lenses Agent to be ready"
kubectl rollout status deployment/lenses-agent -n lenses --timeout=300s

print_info "Waiting 2 minutes for agent to connect to Lenses HQ..."
sleep 120

# Setup car insurance demo
print_step "10" "Setting up Car Insurance Demo"
print_instruction "Check the Lenses HQ UI to verify the Kafka environment is connected"
print_instruction "You should see your environment listed on the Environments page and the status should be green"

read -p "Is the Kafka environment fully set up and connected? (y/n): " env_ready

if [[ "$env_ready" =~ ^[Yy]$ ]]; then
  print_info "Great! Setting up the Car Insurance Demo..."
else
  print_warning "The environment may not be fully set up yet. Let's continue anyway, but you may need to check the setup later."
fi

# Create Car Insurance Demo files
print_info "Creating Car Insurance Demo files"
mkdir -p car-insurance-demo
cd car-insurance-demo

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM python:3.9-slim

WORKDIR /app

# Install required packages
RUN pip install --no-cache-dir kafka-python python-dateutil avro requests

# Copy Python scripts and schema files
COPY producer.py consumer_anonymize.py consumer_billing.py entrypoint.sh ./
COPY schemas/ ./schemas/

# Make the entrypoint script executable
RUN chmod +x entrypoint.sh

# Set the entrypoint
ENTRYPOINT ["./entrypoint.sh"]
EOF

# Create entrypoint.sh
cat > entrypoint.sh << 'EOF'
#!/bin/bash

# Start the producer in the background
python producer.py &

# Give the producer a moment to start and create topics if needed
sleep 5

# Start the anonymizer process in the background
python consumer_anonymize.py &

# Give the anonymizer a moment to start
sleep 5

# Start the billing process in the background
python consumer_billing.py &

# Keep the container running
tail -f /dev/null
EOF
chmod +x entrypoint.sh

# Create schemas directory
mkdir -p schemas

# This script should be combined with setup_part1.sh, setup_part2.sh, and setup_part3.sh

# Create schema_registry.py
cat > schemas/schema_registry.py << 'EOF'
#!/usr/bin/env python3
"""
Schema Registry helper for Avro serialization/deserialization using Confluent Kafka libraries.
"""

import json
import io
import avro.schema
from avro.io import DatumWriter, DatumReader, BinaryEncoder, BinaryDecoder
import struct
import requests

# Magic byte for Confluent Schema Registry format
MAGIC_BYTE = 0

class SchemaRegistry:
    """Schema Registry client for Avro serialization with Kafka."""
    
    def __init__(self, url):
        """Initialize with schema registry URL."""
        self.url = url.rstrip('/')
        self.id_to_schema = {}
        self.subject_to_id = {}
    
    def get_by_id(self, schema_id):
        """Get schema by ID (required for compatibility with MessageSerializer)."""
        if schema_id in self.id_to_schema:
            return self.id_to_schema[schema_id]
        
        response = requests.get(f"{self.url}/schemas/ids/{schema_id}")
        if response.status_code != 200:
            raise Exception(f"Schema registry error: {response.text}")
        
        schema_str = response.json()['schema']
        schema = avro.schema.parse(schema_str)
        self.id_to_schema[schema_id] = schema
        return schema
    
    def register_schema(self, subject, schema_dict):
        """Register schema with the registry and return the ID."""
        schema_str = json.dumps(schema_dict)
        
        # Check if schema is already registered for this subject
        subject_key = f"{subject}:{schema_str}"
        if subject_key in self.subject_to_id:
            return self.subject_to_id[subject_key]
        
        # Register the schema with the registry
        response = requests.post(
            f"{self.url}/subjects/{subject}/versions",
            headers={"Content-Type": "application/vnd.schemaregistry.v1+json"},
            data=json.dumps({"schema": schema_str})
        )
        
        if response.status_code not in (200, 201):
            raise Exception(f"Schema registry error: {response.text}")
        
        schema_id = response.json()['id']
        self.subject_to_id[subject_key] = schema_id
        
        # Also cache the parsed schema
        self.id_to_schema[schema_id] = avro.schema.parse(schema_str)
        
        return schema_id
    
    def encode_record_with_schema(self, record, schema_dict, subject=None):
        """Encode a record with Avro using the Confluent wire format."""
        schema_str = json.dumps(schema_dict)
        parsed_schema = avro.schema.parse(schema_str)
        
        # Get or register the schema
        subject = subject or "car-trips-value"  # Default subject, can be overridden
        schema_id = self.register_schema(subject, schema_dict)
        
        # Encode the record
        writer = DatumWriter(parsed_schema)
        bytes_writer = io.BytesIO()
        
        # Write the magic byte and schema ID
        bytes_writer.write(struct.pack("b", MAGIC_BYTE))
        bytes_writer.write(struct.pack(">I", schema_id))
        
        # Write the record
        encoder = BinaryEncoder(bytes_writer)
        writer.write(record, encoder)
        
        return bytes_writer.getvalue()
    
    def decode_message(self, message_bytes):
        """Decode a message from Confluent wire format."""
        if message_bytes is None:
            return None
        
        bytes_reader = io.BytesIO(message_bytes)
        
        # Read the magic byte and schema ID
        magic_byte = struct.unpack("b", bytes_reader.read(1))[0]
        if magic_byte != MAGIC_BYTE:
            raise Exception(f"Unknown magic byte: {magic_byte}")
        
        schema_id = struct.unpack(">I", bytes_reader.read(4))[0]
        
        # Get the schema
        schema = self.get_by_id(schema_id)
        
        # Decode the record
        reader = DatumReader(schema)
        decoder = BinaryDecoder(bytes_reader)
        return reader.read(decoder)
EOF

# Create car_trip.avsc schema
cat > schemas/car_trip.avsc << 'EOF'
{
  "namespace": "com.lenses.demo.carinsurance",
  "type": "record",
  "name": "CarTrip",
  "fields": [
    {"name": "customerID", "type": "string"},
    {"name": "startingLocationLat", "type": "double"},
    {"name": "startingLocationLon", "type": "double"},
    {"name": "endingLocationLat", "type": "double"},
    {"name": "endingLocationLon", "type": "double"},
    {"name": "distanceTraveledMiles", "type": "double"},
    {"name": "timestamp", "type": "string"}
  ]
}
EOF

# Create anonymized_trip.avsc schema
cat > schemas/anonymized_trip.avsc << 'EOF'
{
  "namespace": "com.lenses.demo.carinsurance",
  "type": "record",
  "name": "AnonymizedTrip",
  "fields": [
    {"name": "customerID", "type": "string"},
    {"name": "startingLocationLat", "type": "string"},
    {"name": "startingLocationLon", "type": "string"},
    {"name": "endingLocationLat", "type": "string"},
    {"name": "endingLocationLon", "type": "string"},
    {"name": "distanceTraveledMiles", "type": "double"},
    {"name": "timestamp", "type": "string"}
  ]
}
EOF

# Create billing.avsc schema
cat > schemas/billing.avsc << 'EOF'
{
  "namespace": "com.lenses.demo.carinsurance",
  "type": "record",
  "name": "Billing",
  "fields": [
    {"name": "customerID", "type": "string"},
    {"name": "distanceTraveledMiles", "type": "double"},
    {"name": "billingAmount", "type": "double"},
    {"name": "timestamp", "type": "string"}
  ]
}
EOF

# This script should be combined with setup_part1.sh, setup_part2.sh, setup_part3.sh, and setup_part4.sh

# Create producer.py
cat > producer.py << 'EOF'
#!/usr/bin/env python3
"""
Producer script for the car insurance demo.
Generates car trip events and sends them to the 'car-trips' Kafka topic.
Uses Avro serialization with schema registry.
"""

import json
import random
import string
import time
import os
import io
from datetime import datetime
from kafka import KafkaProducer
from schemas.schema_registry import SchemaRegistry

# Kafka and Schema Registry configuration
KAFKA_BOOTSTRAP_SERVER = os.getenv('KAFKA_BOOTSTRAP_SERVER', 'PLAINTEXT://my-kafka.kafka.svc.cluster.local:9092')
SCHEMA_REGISTRY_URL = os.getenv('SCHEMA_REGISTRY_URL', 'http://my-schema-registry.kafka.svc.cluster.local:8081')
TOPIC_NAME = 'car-trips'
INTERVAL_SECONDS = float(os.getenv('PRODUCER_INTERVAL_SECONDS', '1.0'))

def generate_customer_id():
    """Generate a random customer ID with 2 letters followed by 8 numbers."""
    letters = ''.join(random.choices(string.ascii_uppercase, k=2))
    numbers = ''.join(random.choices(string.digits, k=8))
    return f"{letters}{numbers}"

def generate_car_trip():
    """Generate a random car trip event."""
    # Determine if this should be a poison pill (5% chance)
    is_poison_pill = random.random() < 0.05
    
    # Generate random coordinates (simplified, not geographically accurate)
    start_lat = round(random.uniform(-90, 90), 6)
    start_lon = round(random.uniform(-180, 180), 6)
    end_lat = round(random.uniform(-90, 90), 6)
    end_lon = round(random.uniform(-180, 180), 6)
    
    # Generate distance - negative for poison pills
    if is_poison_pill:
        distance = round(random.uniform(-100, -1), 2)
    else:
        distance = round(random.uniform(1, 100), 2)
    
    # Create the event with updated field names (no hyphens)
    return {
        "customerID": generate_customer_id(),
        "startingLocationLat": start_lat,
        "startingLocationLon": start_lon,
        "endingLocationLat": end_lat,
        "endingLocationLon": end_lon,
        "distanceTraveledMiles": distance,
        "timestamp": datetime.now().isoformat()
    }

def main():
    """Main function to run the producer."""
    print(f"Connecting to Kafka at {KAFKA_BOOTSTRAP_SERVER}")
    print(f"Using Schema Registry at {SCHEMA_REGISTRY_URL}")
    
    # Load Avro schema
    with open('schemas/car_trip.avsc', 'r') as f:
        schema = json.load(f)
    
    # Create Schema Registry client
    schema_registry = SchemaRegistry(SCHEMA_REGISTRY_URL)
    
    # Define serializer function
    def avro_serializer(value):
        if value is None:
            return None
        
        # Use a specific subject name
        subject = f"{TOPIC_NAME}-value"
        
        # Encode with the subject-specific schema
        return schema_registry.encode_record_with_schema(value, schema, subject)
    
    # Create Kafka producer
    producer = KafkaProducer(
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVER,
        value_serializer=avro_serializer,
        key_serializer=lambda v: v.encode('utf-8') if v else None
    )
    
    # Generate and send events continuously
    try:
        while True:
            # Generate a trip event
            trip = generate_car_trip()
            
            # Use customerID as the key for partitioning
            key = trip["customerID"]
            
            # Send to Kafka
            producer.send(TOPIC_NAME, key=key, value=trip)
            producer.flush()
            
            # Log the event
            trip_type = "POISON PILL" if trip["distanceTraveledMiles"] < 0 else "NORMAL"
            print(f"Sent {trip_type} trip: {trip}")
            
            # Wait before sending the next event
            time.sleep(INTERVAL_SECONDS)
    
    except KeyboardInterrupt:
        print("Producer stopped.")
    finally:
        producer.close()

if __name__ == "__main__":
    # Small delay to ensure Kafka is ready
    time.sleep(10)
    main()
EOF


# This script should be combined with setup_part1.sh through setup_part5.sh

# Create consumer_anonymize.py
cat > consumer_anonymize.py << 'EOF'
#!/usr/bin/env python3
"""
Consumer script that anonymizes car trip data.
Consumes from 'car-trips' topic and produces to 'car-trips-anonymized' topic.
Uses Avro serialization with schema registry.
"""

import json
import os
import time
from kafka import KafkaConsumer, KafkaProducer
from schemas.schema_registry import SchemaRegistry

# Kafka and Schema Registry configuration
KAFKA_BOOTSTRAP_SERVER = os.getenv('KAFKA_BOOTSTRAP_SERVER', 'PLAINTEXT://my-kafka.kafka.svc.cluster.local:9092')
SCHEMA_REGISTRY_URL = os.getenv('SCHEMA_REGISTRY_URL', 'http://my-schema-registry.kafka.svc.cluster.local:8081')
SOURCE_TOPIC = 'car-trips'
DESTINATION_TOPIC = 'car-trips-anonymized'

def anonymize_trip(trip):
    """
    Anonymize the trip data by replacing location data with 'xx'.
    """
    anonymized = trip.copy()
    
    # Replace location data with 'xx' (using updated field names)
    anonymized["startingLocationLat"] = "xx"
    anonymized["startingLocationLon"] = "xx"
    anonymized["endingLocationLat"] = "xx"
    anonymized["endingLocationLon"] = "xx"
    
    return anonymized

def main():
    """Main function to run the anonymizer consumer/producer."""
    print(f"Connecting to Kafka at {KAFKA_BOOTSTRAP_SERVER}")
    print(f"Using Schema Registry at {SCHEMA_REGISTRY_URL}")
    print(f"Consumer: Listening on topic '{SOURCE_TOPIC}'")
    print(f"Producer: Publishing to topic '{DESTINATION_TOPIC}'")
    
    # Create Schema Registry client
    schema_registry = SchemaRegistry(SCHEMA_REGISTRY_URL)
    
    # Load Avro schema for anonymized trips
    with open('schemas/anonymized_trip.avsc', 'r') as f:
        anonymized_schema = json.load(f)
    
    # Define deserialization and serialization functions
    def avro_deserializer(message):
        if message is None:
            return None
        return schema_registry.decode_message(message)
    
    def avro_serializer(value):
        if value is None:
            return None

        # Use a specific subject name for this producer
        subject = f"{DESTINATION_TOPIC}-value"
        
        # Register schema with the specific subject
        schema_id = schema_registry.register_schema(subject, anonymized_schema)
        
        # Encode with the specific schema
        return schema_registry.encode_record_with_schema(value, anonymized_schema, subject)
    
    # Create Kafka consumer with Avro deserializer
    consumer = KafkaConsumer(
        SOURCE_TOPIC,
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVER,
        value_deserializer=avro_deserializer,
        auto_offset_reset='earliest',
        group_id='trip-anonymizer'
    )
    
    # Create Kafka producer with Avro serializer
    producer = KafkaProducer(
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVER,
        value_serializer=avro_serializer,
        key_serializer=lambda v: v.encode('utf-8') if v else None
    )
    
    try:
        # Process messages
        for message in consumer:
            # Get the original trip data
            trip = message.value
            
            # Anonymize the trip data
            anonymized_trip = anonymize_trip(trip)
            
            # Send to the destination topic
            key = anonymized_trip["customerID"]
            producer.send(DESTINATION_TOPIC, key=key, value=anonymized_trip)
            producer.flush()
            
            # Log the event
            print(f"Anonymized trip: {anonymized_trip}")
            
    except KeyboardInterrupt:
        print("Anonymizer stopped.")
    finally:
        consumer.close()
        producer.close()

if __name__ == "__main__":
    # Small delay to ensure Kafka is ready
    time.sleep(10)
    main()
EOF


# This script should be combined with setup_part1.sh through setup_part6.sh

# Create consumer_billing.py
cat > consumer_billing.py << 'EOF'
#!/usr/bin/env python3
"""
Consumer script that generates billing data from anonymized trip data.
Consumes from 'car-trips-anonymized' topic and produces to 'car-trips-billing' topic.
Uses Avro serialization with schema registry.
"""

import json
import os
import time
from kafka import KafkaConsumer, KafkaProducer
from schemas.schema_registry import SchemaRegistry

# Kafka and Schema Registry configuration
KAFKA_BOOTSTRAP_SERVER = os.getenv('KAFKA_BOOTSTRAP_SERVER', 'PLAINTEXT://my-kafka.kafka.svc.cluster.local:9092')
SCHEMA_REGISTRY_URL = os.getenv('SCHEMA_REGISTRY_URL', 'http://my-schema-registry.kafka.svc.cluster.local:8081')
SOURCE_TOPIC = 'car-trips-anonymized'
DESTINATION_TOPIC = 'car-trips-billing'
BILLING_RATE = 0.05  # $0.05 per mile

def calculate_billing(trip):
    """
    Calculate billing information from the trip data.
    """
    # Extract relevant fields (using updated field names)
    customer_id = trip["customerID"]
    distance = trip["distanceTraveledMiles"]
    
    # Calculate billing amount (distance * rate)
    billing_amount = round(distance * BILLING_RATE, 2)
    
    # Create billing record with updated field names
    return {
        "customerID": customer_id,
        "distanceTraveledMiles": distance,
        "billingAmount": billing_amount,
        "timestamp": trip["timestamp"]
    }

def main():
    """Main function to run the billing consumer/producer."""
    print(f"Connecting to Kafka at {KAFKA_BOOTSTRAP_SERVER}")
    print(f"Using Schema Registry at {SCHEMA_REGISTRY_URL}")
    print(f"Consumer: Listening on topic '{SOURCE_TOPIC}'")
    print(f"Producer: Publishing to topic '{DESTINATION_TOPIC}'")
    
    # Create Schema Registry client
    schema_registry = SchemaRegistry(SCHEMA_REGISTRY_URL)
    
    # Load Avro schema for billing
    with open('schemas/billing.avsc', 'r') as f:
        billing_schema = json.load(f)
    
    # Define deserialization and serialization functions
    def avro_deserializer(message):
        if message is None:
            return None
        return schema_registry.decode_message(message)
    
    def avro_serializer(value):
        if value is None:
            return None
            
        # Use a specific subject name for this producer
        subject = f"{DESTINATION_TOPIC}-value"
        
        # Register schema with the specific subject
        schema_id = schema_registry.register_schema(subject, billing_schema)
        
        # Encode with the specific schema
        return schema_registry.encode_record_with_schema(value, billing_schema, subject)
    
    # Create Kafka consumer with Avro deserializer
    consumer = KafkaConsumer(
        SOURCE_TOPIC,
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVER,
        value_deserializer=avro_deserializer,
        auto_offset_reset='earliest',
        group_id='trip-billing'
    )
    
    # Create Kafka producer with Avro serializer
    producer = KafkaProducer(
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVER,
        value_serializer=avro_serializer,
        key_serializer=lambda v: v.encode('utf-8') if v else None
    )
    
    try:
        # Process messages
        for message in consumer:
            # Get the anonymized trip data
            trip = message.value
            
            # Calculate billing information
            billing_info = calculate_billing(trip)
            
            # Send to the destination topic
            key = billing_info["customerID"]
            producer.send(DESTINATION_TOPIC, key=key, value=billing_info)
            producer.flush()
            
            # Log the event
            bill_type = "NEGATIVE BILL" if billing_info["billingAmount"] < 0 else "NORMAL BILL"
            print(f"Created {bill_type}: {billing_info}")
            
    except KeyboardInterrupt:
        print("Billing processor stopped.")
    finally:
        consumer.close()
        producer.close()

if __name__ == "__main__":
    # Small delay to ensure Kafka is ready
    time.sleep(10)
    main()
EOF


# This script should be combined with setup_part1.sh through setup_part7.sh

# Create build-and-deploy.sh script
cat > build-and-deploy.sh << 'EOF'
#!/bin/bash
# Script to build and deploy the car insurance demo

# Set color output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Check Minikube status
echo -e "${BLUE}Checking Minikube status...${NC}"
minikube status || { echo -e "${RED}Minikube is not running. Please start it first.${NC}"; exit 1; }

# Configure shell to use Minikube's Docker daemon
echo -e "${BLUE}Configuring to use Minikube's Docker daemon...${NC}"
eval $(minikube docker-env)

# Build the Docker image
echo -e "${BLUE}Building Docker image...${NC}"
docker build -t car-insurance-demo:latest .

# Create Kubernetes deployment file
cat > deployment.yaml << 'EOL'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: car-insurance-demo
  namespace: kafka
  labels:
    app: car-insurance-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: car-insurance-demo
  template:
    metadata:
      labels:
        app: car-insurance-demo
    spec:
      containers:
      - name: demo-container
        image: car-insurance-demo:latest
        imagePullPolicy: Never
        env:
        - name: KAFKA_BOOTSTRAP_SERVER
          value: "PLAINTEXT://my-kafka.kafka.svc.cluster.local:9092"
        - name: SCHEMA_REGISTRY_URL
          value: "http://my-schema-registry.kafka.svc.cluster.local:8081"
        - name: PRODUCER_INTERVAL_SECONDS
          value: "1.0"
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "200m"
EOL

# Deploy to Kubernetes
echo -e "${BLUE}Deploying to Kubernetes...${NC}"
kubectl apply -f deployment.yaml

# Wait for the deployment to be ready
echo -e "${BLUE}Waiting for deployment to be ready...${NC}"
kubectl rollout status deployment/car-insurance-demo -n kafka --timeout=300s

echo -e "${GREEN}Car Insurance Demo has been deployed successfully!${NC}"
echo -e "${YELLOW}You can view the logs with:${NC} kubectl logs -n kafka deployment/car-insurance-demo -f"
EOF
chmod +x build-and-deploy.sh

# Create a README file for the demo
cat > README.md << 'EOF'
# Car Insurance Demo for Lenses.io

This demo simulates a car insurance company that tracks customer trips and bills them based on mileage.

## Components

1. **Producer**: Generates car trip events with:
   - Customer ID
   - Starting/ending location coordinates
   - Distance traveled in miles
   - Timestamp
   
   (5% of events have negative distance as "poison pills")

2. **Anonymizer**: Removes location data for privacy, replacing coordinates with "xx"

3. **Billing Processor**: Calculates charges based on miles traveled (at $0.05 per mile)

## Demo Flow in Lenses.io

1. View raw trip data in the `car-trips` topic
2. Observe anonymized data in the `car-trips-anonymized` topic
3. See billing calculations in the `car-trips-billing` topic
4. Create a SQL processor to filter out negative bills (from poison pills)

## Running the Demo

1. Make sure Minikube and Lenses.io are set up and running
2. Execute `./build-and-deploy.sh` to build and deploy the demo
3. Open the Lenses.io UI to observe the data flowing through the topics

## Topics

- `car-trips` - Raw trip data with location information
- `car-trips-anonymized` - Trip data with location information anonymized
- `car-trips-billing` - Billing data derived from anonymized trips
EOF


# This script should be combined with setup_part1.sh through setup_part8.sh

# Deploy the car insurance demo
print_step "11" "Deploying the Car Insurance Demo"
print_info "Building and deploying the demo container..."
./build-and-deploy.sh

# Wait a bit for data to start flowing
print_info "Waiting for data to start flowing into Kafka topics (30 seconds)..."
sleep 30

# Final instructions
print_step "12" "Setup Complete!"
print_success "The Lenses.io demo environment with Car Insurance Demo is now fully set up!"
print_instruction "You can now explore the demo in the Lenses HQ UI at http://127.0.0.1:8080"
print_instruction "Follow these steps to explore the demo:"
echo "1. Go to Topics section in Lenses UI and inspect the following topics:"
echo "   - car-trips (raw trip data with location information)"
echo "   - car-trips-anonymized (data with locations replaced by 'xx')"
echo "   - car-trips-billing (calculated billing amounts, including negative bills from 'poison pills')"
echo ""
echo "2. Create a SQL Processor to filter out negative bills:"
echo "   - In Lenses UI, go to SQL section"
echo "   - Create a new processor with a query like:"
echo "     SELECT * FROM \`car-trips-billing\` WHERE billingAmount > 0 SINK INTO \`car-trips-filtered-billing\`"
echo ""
print_warning "Remember to keep the port-forward running in your other terminal to access the Lenses HQ UI"
print_info "For questions, please email: drew.oetzel.ext@lenses.io"

cd ../../

