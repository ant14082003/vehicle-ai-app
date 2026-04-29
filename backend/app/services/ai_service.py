from sentence_transformers import SentenceTransformer
import numpy as np
import faiss
import os

# Load model
model = SentenceTransformer('all-MiniLM-L6-v2')

# Load index safely
if os.path.exists("manual.index"):
    index = faiss.read_index("manual.index")
else:
    index = None

# Load manual text
with open("app/sample_manual.txt", "r") as f:
    manual_lines = [line.strip() for line in f.readlines() if line.strip() != ""]

def get_answer(question: str):

    if index is None:
        return {
            "answer": "AI system not ready. Manual index not created yet.",
            "sources": []
        }

    q_embedding = model.encode([question])

    distances, indices = index.search(np.array(q_embedding), k=1)

    best_idx = indices[0][0]

    if best_idx < len(manual_lines):
        answer = manual_lines[best_idx]
    else:
        answer = "No relevant information found."

    return {
        "answer": answer,
        "sources": [answer]
    }