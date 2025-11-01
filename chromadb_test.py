import chromadb
from chromadb.utils import embedding_functions
import time
from fastapi import FastAPI
from pydantic import BaseModel




#we create the chroma client , the embedding function and we get the collection
chroma_client = chromadb.HttpClient(host='91.134.37.11', port=8055)
emb_fn  = embedding_functions.SentenceTransformerEmbeddingFunction(model_name = 'paraphrase-multilingual-MiniLM-L12-v2')
collection1 = chroma_client.get_collection(name = "novaia_main_intents",embedding_function = emb_fn)
collection2 = chroma_client.get_collection(name = "novaia_faqs_intents",embedding_function = emb_fn)
#we instantiate the fastapi app
app = FastAPI()



#we create the sentence class
class Sentence(BaseModel):
    sentence:str


@app.post("/embedding_main/")
async def get_embedding_main(input: Sentence):
    try:
        result = collection1.query(
            query_texts=[input.sentence],
            n_results=1
        )
        distance = result['distances'][0][0]
        label = result['metadatas'][0][0]['label']
        
        if distance <= 0.19:
            return {"intent": label}
        else:
            return {"intent": "unknown"}
    except Exception as e:
        return {"error": str(e)}
    


@app.post("/embedding_faqs/")
async def get_embedding(input:Sentence):
    result = collection2.query(
    query_texts=[input.sentence],
    n_results=1
)
    distance = result['distances'][0][0]
    label = result['metadatas'][0][0]['label']
    if distance <= 0.19:
        return {"intent":label}
    else:
        return {"intent":"faq24"}
    

