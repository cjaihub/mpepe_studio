import chromadb
import os
import logging
from typing import List

logger = logging.getLogger(__name__)

class RAGEngine:
    def __init__(self, db_path: str = "./data/chroma_db"):
        os.makedirs(db_path, exist_ok=True)
        try:
            self.client = chromadb.PersistentClient(path=db_path)
            self.collection = self.client.get_or_create_collection(name="color_theory")
            logger.info("RAG Engine initialized successfully.")
        except Exception as e:
            logger.error(f"Failed to initialize RAG Engine: {e}")
            self.client = None
            self.collection = None

    def ingest_document(self, doc_id: str, text: str):
        if not self.collection:
            return False
            
        # Basic chunking: split by paragraphs
        chunks = [c.strip() for c in text.split('\n\n') if len(c.strip()) > 50]
        if not chunks:
            return False
            
        ids = [f"{doc_id}_{i}" for i in range(len(chunks))]
        try:
            self.collection.upsert(
                documents=chunks,
                ids=ids,
                metadatas=[{"source": doc_id} for _ in chunks]
            )
            logger.info(f"Ingested document {doc_id} with {len(chunks)} chunks.")
            return True
        except Exception as e:
            logger.error(f"Failed to ingest document: {e}")
            return False

    def query_theory(self, prompt: str, n_results: int = 2) -> str:
        """Retrieves relevant grading theory for the given prompt."""
        if not self.collection:
            return ""
            
        try:
            results = self.collection.query(
                query_texts=[prompt],
                n_results=n_results
            )
            
            documents = results.get("documents", [])
            if documents and documents[0]:
                return "\n".join(documents[0])
            return ""
        except Exception as e:
            logger.error(f"Failed to query RAG Engine: {e}")
            return ""

# Singleton instance
rag = RAGEngine()
