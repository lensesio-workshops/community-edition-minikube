#!/usr/bin/env python3
"""
Consumer script that anonymizes car trip data.
Consumes from 'car-trips' topic and produces to 'car-trips-anonymized' topic.
"""

import json
import os
import time
from kafka import KafkaConsumer, KafkaProducer

# Kafka configuration
KAFKA_BOOTSTRAP_SERVER = os.getenv('KAFKA_BOOTSTRAP_SERVER', 'kafka-0.kafka-headless.kafka.svc.cluster.local:9092')
SOURCE_TOPIC = 'car-trips'
DESTINATION_TOPIC = 'car-trips-anonymized'

def anonymize_trip(trip):
    """
    Anonymize the trip data by replacing location data with 'xx'.
    """
    anonymized = trip.copy()
    
    # Replace location data with 'xx'
    anonymized["starting-locationLat"] = "xx"
    anonymized["starting-locationLon"] = "xx"
    anonymized["ending-locationLat"] = "xx"
    anonymized["ending-locationLon"] = "xx"
    
    return anonymized

def main():
    """Main function to run the anonymizer consumer/producer."""
    print(f"Connecting to Kafka at {KAFKA_BOOTSTRAP_SERVER}")
    print(f"Consumer: Listening on topic '{SOURCE_TOPIC}'")
    print(f"Producer: Publishing to topic '{DESTINATION_TOPIC}'")
    
    # Create Kafka consumer
    consumer = KafkaConsumer(
        SOURCE_TOPIC,
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVER,
        value_deserializer=lambda x: json.loads(x.decode('utf-8')),
        auto_offset_reset='earliest',
        group_id='trip-anonymizer'
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
