FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

//EXPOSE 8000
//CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
//Se actualizo Dockerfile para que use el puerto que Railway provee en la variable port
ENV PORT 8000

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
