# Use an official Python runtime
FROM python:3.9-slim

# Set Pub/Sub topic name
ENV PUBSUB_TOPIC_NAME=""

# Set Cloud Storage bucket name
ENV BUCKET_NAME=""

# Set socket path
ENV SOCKET_PATH=""

# Set working directory
WORKDIR /app

# Copy the current directory contents into the container at /app
COPY . /app

# Upgrade pip and install the required packages specified in requirements.txt
RUN pip install --upgrade pip \ 
 && pip install --no-cache-dir -r requirements.txt

# Run `server.py` when the container launches
CMD ["python", "server.py"]
