import os
from dataclasses import dataclass
from typing import Optional
from dotenv import load_dotenv



#we load the environement variables 
load_dotenv()

@dataclass
class Config:
    
    #the network
    RTP_IP:str = os.getenv('RTP_IP','0.0.0.0')
    RTP_PORT:int = int(os.getenv('RTP_PORT','8766'))

    #whisper
    WHISPER_URL :str = os.getenv('WHISPER_URL','http://localhost:8080/whisper')
    WHISPER_TIMEOUT: int = int(os.getenv('WHISPER_TIMEOUT', '30'))
    
    #chromadb
    CHROMA_HOST: str = os.getenv('CHROMADB_HOST', 'http://localhost:8056')

    # Audio
    VAD_THRESHOLD: float = float(os.getenv('VAD_THRESHOLD', '0.5'))
    SAMPLE_RATE: int = int(os.getenv('SAMPLE_RATE', '16000'))
    CHUNK_SIZE: int = int(os.getenv('CHUNK_SIZE', '512'))
    SILENCE_THRESHOLD :float = float(os.getenv('SILENCE_THRESHOLD',1))



    #Buffers
    MAX_BUFFER_SIZE: int = int(os.getenv('MAX_BUFFER_SIZE', '32000'))
    SILENCE_CHUNKS_CONTEXT: int = int(os.getenv('SILENCE_CHUNKS_CONTEXT', '2'))
    
    # Logging
    LOG_LEVEL: str = os.getenv('LOG_LEVEL', 'INFO')

