#!/bin/bash

set -e

echo "🧱 Instalando Minikube..."
curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
rm minikube-linux-amd64

echo "🔧 Instalando kubectl..."
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install kubectl /usr/local/bin/kubectl
rm kubectl

echo "🚀 Iniciando Minikube..."
minikube start

echo "📦 Instalando arkade..."
curl -sLS https://get.arkade.dev | sudo sh

echo "🧠 Instalando OpenFaaS con arkade..."
arkade install openfaas

echo "🔁 Esperando a que el gateway de OpenFaaS esté listo..."
kubectl rollout status -n openfaas deploy/gateway

echo "🌐 Redireccionando puerto 8080 al gateway..."
kubectl port-forward -n openfaas svc/gateway 8080:8080 &

echo "🔐 Instalando faas-cli..."
curl -sSL https://cli.openfaas.com | sudo sh

echo "🔓 Autenticando en OpenFaaS..."
PASSWORD=$(kubectl get secret -n openfaas basic-auth -o jsonpath="{.data.basic-auth-password}" | base64 --decode)
echo "$PASSWORD" | faas-cli login --username admin --password-stdin

echo "📚 Obteniendo plantilla python3-http-debian..."
faas-cli template store pull python3-http-debian

echo "📁 Creando estructura de función..."
faas-cli new face-detect --lang python3-http-debian

echo "✏️ Escribiendo handler.py..."
cat > face-detect/handler.py << EOF
import base64
import cv2
import numpy as np
import requests
import json

def handle(event, context):
    try:
        data = event.body
        if isinstance(data, bytes):
            data = data.decode('utf-8')

        parsed = json.loads(data)
        url = parsed.get("image_url", "")

        if not url:
            return "Missing 'image_url' in request", 400

        response = requests.get(url, timeout=10)
        if response.status_code != 200:
            return "Failed to download image", 400

        img_array = np.frombuffer(response.content, np.uint8)
        img = cv2.imdecode(img_array, cv2.IMREAD_COLOR)

        if img is None:
            return "Invalid image format", 400

        face_cascade = cv2.CascadeClassifier(
            cv2.data.haarcascades + 'haarcascade_frontalface_default.xml'
        )

        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        faces = face_cascade.detectMultiScale(gray, 1.1, 4)

        for (x, y, w, h) in faces:
            cv2.rectangle(img, (x, y), (x+w, y+h), (0, 255, 0), 2)

        _, buffer = cv2.imencode('.jpg', img)
        img_base64 = base64.b64encode(buffer).decode('utf-8')

        return img_base64

    except Exception as e:
        return f"Unhandled error: {str(e)}", 500
EOF

echo "📝 Creando requirements.txt..."
cat > face-detect/requirements.txt << EOF
opencv-python
numpy
requests
EOF

echo "📦 Creando stack.yaml..."
cat > stack.yaml << EOF
version: 1.0
provider:
  name: openfaas
  gateway: http://127.0.0.1:8080
functions:
  face-detect:
    lang: python3-http-debian
    handler: ./face-detect
    image: alexcolladodev2/face-detect:latest
    build_args:
      ADDITIONAL_PACKAGE: "libgl1-mesa-glx libglib2.0-0"
EOF

echo "🔨 Compilando función..."
faas-cli build -f stack.yaml --no-cache

#echo "🚢 Enviando imagen a Docker Hub..."
#docker tag local/face-detect alexcolladodev2/face-detect:latest
#docker push alexcolladodev2/face-detect:latest

echo "📤 Desplegando función en OpenFaaS..."
faas-cli deploy -f stack.yaml

echo "✅ Función desplegada. Estado actual:"
faas-cli list
kubectl get pods -n openfaas-fn

echo "🧪 Ejecutando prueba con imagen alternativa..."
curl -X POST http://localhost:8080/function/face-detect \
  -H "Content-Type: application/json" \
  -d '{"image_url": "https://raw.githubusercontent.com/opencv/opencv/master/samples/data/lena.jpg"}' \
  --output result.b64

base64 -d result.b64 > result.jpg

echo "✅ Imagen guardada como result.jpg. Proceso completado correctamente."
