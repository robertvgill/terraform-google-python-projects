# Use an official Python runtime
FROM python:3.9-slim

# Set environment variables
ENV INPUT_FOLDER=""
ENV OUTPUT_FOLDER=""
ENV PGCONNINFO=""

# Set the working directory in the container
# Set working directory
WORKDIR /app

# Copy the current directory contents into the container at /app
COPY . /app

# Upgrade pip and install the required packages specified in requirements.txt
RUN pip install --upgrade pip \ 
 && pip install --no-cache-dir -r requirements.txt

# Run `schedule.py` when the container launches
CMD ["python", "schedule.py"]
