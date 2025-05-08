#!/usr/bin/env python3
"""
Producer script for the car insurance demo.
Generates car trip events and sends them to the 'car-trips' Kafka topic.
"""

import json
import random
import string
import time
import os
from datetime import datetime
from kafka import KafkaProducer

# Kafka configuration
KAFKA_BOOTSTRAP_SERVER = os.getenv('KAFKA_BOOTSTRAP_SERVER', 'kafka-0.kafka-headless.kafka.svc.cluster.local:9092')
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
    
    # Create the event
    return {
        "customerID": generate_customer_id(),
        "starting-locationLat": start_lat,
        "starting-locationLon": start_lon,
        "ending-locationLat": end_lat,
        "ending-locationLon": end_lon,
        "distance-traveled-miles": distance,
        "timestamp": datetime.now().isoformat()
    }

def main():
    """Main function to run the producer."""
    print(f"Connecting to Kafka at {KAFKA_BOOTSTRAP_SERVER}")
    
    # Create Kafka producer
    producer = KafkaProducer(
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVER,
        value_serializer=lambda v: json.dumps(v).encode('utf-8'),
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
            trip_type = "POISON PILL" if trip["distance-traveled-miles"] < 0 else "NORMAL"
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
