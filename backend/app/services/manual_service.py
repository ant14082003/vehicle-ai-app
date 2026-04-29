from sentence_transformers import SentenceTransformer

model = SentenceTransformer("all-MiniLM-L6-v2")

import faiss
import numpy as np

dimension = 384

index = faiss.IndexFlatL2(dimension)

index.add(np.array(embeddings))

faiss.write_index(index,"manual.index")