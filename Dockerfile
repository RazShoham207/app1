# Use the official image as a parent image
FROM python:3.8-slim

# Set the working directory in the container
WORKDIR /app

# Copy the current directory contents into the container at /app
ADD . /app

# Install any needed packages specified in requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Update Flask and Werkzeug
RUN pip install --upgrade Flask Werkzeug

# Verify installed versions
RUN pip show Flask Werkzeug

# Generate SSL certificate and key
RUN apt-get update && apt-get install -y openssl && \
    openssl genrsa -out /app/tls.key 2048 && \
    openssl req -new -key /app/tls.key -out /app/tls.csr -subj "/CN=localhost" && \
    openssl x509 -req -days 365 -in /app/tls.csr -signkey /app/tls.key -out /app/tls.crt

# Install dnsutils for nslookup
RUN apt-get install -y dnsutils

# Install systemd and other necessary packages
RUN apt-get install -y systemd && apt-get clean

# Install iputils-ping for ping
RUN apt-get install -y iputils-ping

# Install curl for debugging
RUN apt-get install -y curl

# Install smbclient and cifs-utils for SMB connectivity testing
RUN apt-get install -y smbclient cifs-utils

# Make port 443 available to the world outside this container
EXPOSE 443

# Run app.py when the container launches
CMD ["gunicorn", "--certfile=/app/tls.crt", "--keyfile=/app/tls.key", "-b", "0.0.0.0:443", "app:app"]
