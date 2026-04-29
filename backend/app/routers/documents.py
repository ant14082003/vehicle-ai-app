from fastapi import APIRouter
import requests
import pytesseract
from PIL import Image
from io import BytesIO

pytesseract.pytesseract.tesseract_cmd = r"C:\Program Files\Tesseract-OCR\tesseract.exe"
router = APIRouter(prefix="/documents")

@router.post("/process")
def process_document(data: dict):

    image_url = data.get("imageUrl")

    # Download image
    response = requests.get(image_url)
    img = Image.open(BytesIO(response.content))

    # OCR
    text = pytesseract.image_to_string(img)

    print("OCR TEXT:\n", text)

    # Simple extraction
    registration = "UNKNOWN"

    for word in text.split():
        if any(char.isdigit() for char in word) and len(word) > 6:
            registration = word
            break

    return {
        "message": f"Detected Registration: {registration}"
    }