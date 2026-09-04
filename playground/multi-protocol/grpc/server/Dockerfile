FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY echo.proto .
RUN python -m grpc_tools.protoc -I. --python_out=. --grpc_python_out=. echo.proto
COPY server.py .

EXPOSE 8891
CMD ["python", "server.py"]
