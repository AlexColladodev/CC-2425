import base64
import cv2
import numpy as np
import requests
import json

def handle(event, context):
    try:
        print("Raw event body:")
        print(event.body)

        data = event.body
        if isinstance(data, bytes):
            data = data.decode('utf-8')

        parsed = json.loads(data)
        url = parsed.get("image_url", "")

        print(f"Parsed URL: {url}")

        if not url:
            return "Missing 'image_url' in request", 400

        try:
            response = requests.get(url, timeout=10)
            response.raise_for_status()
        except Exception as e:
            return f"Error downloading image: {str(e)}", 400

        img_array = np.frombuffer(response.content, np.uint8)
        img = cv2.imdecode(img_array, cv2.IMREAD_COLOR)

        if img is None:
            return "Image could not be decoded by OpenCV", 400

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

    except json.JSONDecodeError as e:
        return f"Invalid JSON: {str(e)}", 400
    except Exception as e:
        return f"Unhandled error: {str(e)}", 500
