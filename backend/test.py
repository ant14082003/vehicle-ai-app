# Run this as a separate test script — save as test_gemini.py and run with python test_gemini.py
from google import genai

client = genai.Client(api_key="AIzaSyCxeDYk_050kMRrPxLhTJwGqB_RWAF7TVU")

for model in client.models.list():
    print(model.name)