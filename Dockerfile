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

# # Print installed versions
# RUN python -c "import flask; import werkzeug; print('Flask version:', flask.__version__); print('Werkzeug version:', werkzeug.__version__)"

# Make port 80 available to the world outside this container
EXPOSE 80

# Run app.py when the container launches
CMD ["python", "app.py"]
