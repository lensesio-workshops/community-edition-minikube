#!/usr/bin/env python3
"""
Consumer script that generates billing data from anonymized trip data.
Consumes from 'car-trips-anonymized' topic and produces to 'car-trips-billing' topic.
"""

import json
import os
import time
from kafka import KafkaConsumer, KafkaProducer

# Kafka configuration
KAFKA_BOOTSTRAP_SERVER = os.getenv('KAFKA_BOOTSTRAP_SERVER', 'kafka-0.kafka-headless.kafka.svc.cluster.local:9092')
SOURCE_TOPIC = 'car-trips-anonymized'
DESTINATION_TOPIC = 'car-trips-billing'
BILLING_RATE = 0.05  # $0.05 per mile

def calculate_billing(trip):
    """
    Calculate billing information from the trip data.
    """
    # Extract relevant fields
    customer_id = trip["customerID"]
    distance = trip["distance-traveled-miles"]
    
    # Calculate billing amount (distance * rate)
    billing_amount = round(distance * BILLING_RATE, 2)
    
    # Create billing record
    return {
        "customerID": customer_id,
        "distance-traveled-miles": distance,
        "billing-amount": billing_amount,
        "timestamp": trip["timestamp"]
    }

def main():
    """Main function to run the billing consumer/producer."""
    print(f"Connecting to Kafka at {KAFKA_BOOTSTRAP_SERVER}")
    print(f"Consumer: Listening on topic '{SOURCE_TOPIC}'")
    print(f"Producer: Publishing to topic '{DESTINATION_TOPIC}'")
    
    # Create Kafka consumer
    consumer = KafkaConsumer(
        SOURCE_TOPIC,
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVER,
        value_deserializer=lambda x: json.loads(x.decode('utf-8')),
        auto_offset_reset='earliest',
        group_id='trip-billing'
    )
    
    # Create Kafka producer
    producer = KafkaProducer(
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVER,
        value_serializer=lambda v: json.dumps(v).encode('utf-8'),
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
            bill_type = "NEGATIVE BILL" if billing_info["billing-amount"] < 0 else "NORMAL BILL"
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
