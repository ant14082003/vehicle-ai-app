from sentence_transformers import SentenceTransformer
import faiss
import numpy as np

# Load model
model = SentenceTransformer('all-MiniLM-L6-v2')

# Read manual
with open("app/sample_manual.txt", "r") as f:
    lines = f.readlines()

# Clean lines
texts = [line.strip() for line in lines if line.strip() != ""]

# Create embeddings
embeddings = model.encode(texts)

# Convert to numpy
embeddings = np.array(embeddings)

# Create FAISS index
dimension = embeddings.shape[1]
index = faiss.IndexFlatL2(dimension)

# Add embeddings
index.add(embeddings)

# Save index
faiss.write_index(index, "manual.index")

print("✅ manual.index created successfully")