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
