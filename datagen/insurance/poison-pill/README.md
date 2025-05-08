# Kafka Car Insurance Demo Container

This project contains a Docker container that runs three Python processes for a Kafka-based car insurance demo from lenses.io.

## Overview

The demo simulates a car insurance company that tracks customer driving and bills them based on mileage:

1. **Producer**: Generates simulated car trip data with the following fields:
   - customerID (2 letters + 8 numbers)
   - starting-locationLon/Lat
   - ending-locationLon/Lat
   - distance-traveled-miles (random 1-100, with 5% negative "poison pills")
   - timestamp

2. **Anonymizer**: Consumes from the `car-trips` topic, anonymizes location data, and produces to `car-trips-anonymized`.

3. **Billing Processor**: Consumes from the `car-trips-anonymized` topic, calculates billing (distance × $0.05), and produces to `car-trips-billing`.

## Build and Run

### Build the Docker image:

```bash
docker build -t car-insurance-kafka-demo .
```

### Run the container:

```bash
docker run -e KAFKA_BOOTSTRAP_SERVER=your-kafka-bootstrap-server:9092 car-insurance-kafka-demo
```

## Environment Variables

- `KAFKA_BOOTSTRAP_SERVER`: Kafka bootstrap server (default: `kafka-0.kafka-headless.kafka.svc.cluster.local:9092`)
- `PRODUCER_INTERVAL_SECONDS`: Interval between producing events (default: `1.0`)

## For Kubernetes/Minikube Deployment

If deploying alongside the Bitnami Kafka Helm chart in Minikube:

1. Deploy Kafka using the provided values.yaml:
   ```bash
   helm install kafka bitnami/kafka -f values.yaml -n kafka --create-namespace
   ```

2. Deploy this demo container:
   ```bash
   kubectl apply -f deployment.yaml
   ```

## Expected Topics

This demo will use/create the following Kafka topics:
- `car-trips` - Raw trip data
- `car-trips-anonymized` - Anonymized trip data
- `car-trips-billing` - Billing data with calculated charges

## Demo Flow

1. Producer generates car trip events (including 5% with negative distances as "poison pills")
2. Anonymizer removes location data
3. Billing processor calculates charges
4. Lenses SQL processor (external to this container) can be used to filter out negative bills
