# Use an official Python runtime
FROM python:3.9-slim

# Set persistent volume claim name
ENV PVC_NAME=""

# Set namespace
ENV NAMESPACE=""

# Set retention days for keeping the snapshots
ENV MAX_RETENTION_DAYS=""

# Set working directory
WORKDIR /app

# Copy the current directory contents into the container at /app
COPY . /app

# Upgrade pip and install the `kubernetes` package
RUN pip install --upgrade pip \
 && pip install kubernetes

# Run `snapshot.py` when the container launches
CMD ["python", "./snapshot.py"]

