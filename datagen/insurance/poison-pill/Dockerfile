FROM python:3.9-slim

WORKDIR /app

# Install required packages
RUN pip install --no-cache-dir kafka-python python-dateutil

# Copy Python scripts
COPY producer.py consumer_anonymize.py consumer_billing.py entrypoint.sh ./

# Make the entrypoint script executable
RUN chmod +x entrypoint.sh

# Set the entrypoint
ENTRYPOINT ["./entrypoint.sh"]
