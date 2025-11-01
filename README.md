# Documentation Technique - Système de Téléphonie IA

## 1. Architecture du système

### 1.1 Vue d'ensemble
Le système implémente une solution de téléphonie conversationnelle basée sur Asterisk ARI, permettant de traiter des appels téléphoniques avec un bot intelligent utilisant la reconnaissance vocale et l'analyse d'intentions.

### 1.2 Stack technologique
- **Téléphonie** : Asterisk 18+ avec ARI (Asterisk REST Interface)
- **Reconnaissance vocale** : Faster-Whisper (modèle large-v3)
- **Détection vocale** : Silero VAD (Voice Activity Detection)
- **Framework ML** : PyTorch + TorchAudio
- **APIs** : FastAPI, Flask
- **Cache/État** : Redis
- **Audio streaming** : RTP (Real-time Transport Protocol)

## 2. Composants du système

### 2.1 Bot Manager (`bot_manager.py`)

#### Responsabilités
- Gestion du flux de conversation par machine à états
- Intégration avec l'API de classification d'intentions
- Gestion des compteurs de tentatives et objections
- Logique métier du parcours client

#### Machine à états
```python
États : init → ask_zip_code → ask_owner_house → ask_which_heating 
       → ask_be_called_back → ask_slot_call_back → bye
```

#### Classification d'intentions
- **API principale** : `http://91.134.37.11:8056/embedding_main/`
- **API fallback** : `http://91.134.37.11:8056/embedding_faqs/`
- **Timeout** : 5 secondes avec gestion d'erreurs

#### Intentions reconnues
| Intention | Description |
|-----------|-------------|
| `ok_eligibility`, `ok_zipcode`, `ok_proprio`, `ok_callback` | Acceptations |
| `no_callback`, `not_in_france`, `not_proprio` | Refus |
| `which_help`, `zipcode_why` | Demandes d'information |
| `faq1` à `faq24` | Questions fréquentes |

#### Gestion des compteurs
```python
self.counters = {
    'zip_code_why': 0,      # Max 1 explication code postal
    'not_call_back': 0,     # Max 1 refus de rappel
    'slot_call_back': 0,    # Max 1 problème de créneau
    'busy': 0,              # Max 1 "je suis occupé"
    'not_interested': 0     # Max 1 désintéressement
}
```

### 2.2 Configuration (`config.py`)

#### Structure de configuration
```python
@dataclass
class Config:
    # Réseau
    RTP_IP: str = '0.0.0.0'
    RTP_PORT: int = 8766
    
    # Whisper
    WHISPER_URL: str = 'http://localhost:8080/whisper'
    WHISPER_TIMEOUT: int = 30
    
    # Audio processing
    VAD_THRESHOLD: float = 0.5
    SAMPLE_RATE: int = 16000
    CHUNK_SIZE: int = 512
    SILENCE_THRESHOLD: float = 1.0
    
    # Buffer management
    MAX_BUFFER_SIZE: int = 32000
    SILENCE_CHUNKS_CONTEXT: int = 2
```

### 2.3 Contrôleur ARI (`outband_ari.py`)

#### Responsabilités principales
- Interface avec Asterisk via ARI
- Gestion du cycle de vie des canaux
- Orchestration audio (lecture/enregistrement)
- Gestion d'état distribué via Redis

#### Types de canaux gérés
1. **Canaux principaux** : Appels entrants normaux
2. **Canaux de snooping** : Capture audio entrante (`spy="in"`)
3. **Canaux d'enregistrement** : Capture bidirectionnelle (`spy="both"`)
4. **Canaux external media** : Streaming RTP vers services externes

#### Workflow de création de canal
```python
1. StasisStart event → Canal principal
2. channel.answer() → Réponse à l'appel  
3. Lecture message d'accueil
4. Création canal snooping (spy="in")
5. Création canal enregistrement (spy="both")
6. Création external media + bridge RTP
```

#### Gestion des événements ARI
- **StasisStart** : Nouveau canal entrant
- **StasisEnd** : Nettoyage ressources canal
- **PlaybackStarted** : Début lecture audio
- **PlaybackFinished** : Fin lecture + gestion raccrochage

#### État bot speaking
```python
# Redis key: "bot_speaking"
# Values: "True" | "False"
# Usage: Éviter traitement audio pendant que bot parle
```

### 2.4 Récepteur RTP (`external_media_file.py`)

#### Architecture de traitement
```
RTP Packets → SLIN16 Decode → Float32 Convert → VAD Analysis 
           → Speech Buffering → Whisper Transcription → Intent Processing
```

#### Voice Activity Detection (VAD)
- **Modèle** : Silero VAD via torch.hub
- **Seuil** : Configurable (défaut 0.5)
- **Chunk size** : 512 échantillons
- **Post-speech silence** : 2 chunks pour déclencher traitement

#### Algorithme de buffering
```python
if confidence >= vad_threshold:
    # Parole détectée
    if not self.to_process and self.silence_buffer:
        # Ajouter contexte de silence précédent
        self.to_process.extend(self.silence_buffer)
    self.to_process.append(chunk)
    self.post_speech_silence_count = 0
else:
    # Silence détecté
    if self.to_process:
        self.post_speech_silence_count += 1
        if self.post_speech_silence_count >= 2:
            # Déclencher transcription
            process_speech_chunks()
```

#### Intégration Redis
- **Vérification état bot** : Lecture synchrone de `bot_speaking`
- **Logique conditionnelle** : Pas de traitement si bot parle
- **Gestion erreurs** : Fallback graceful si Redis indisponible

### 2.5 Service Whisper (`whisper_ari.py`)

#### Configuration modèle
```python
model_size = "large-v3"
device = "cuda" if torch.cuda.is_available() else "cpu"
compute_type = "float16"  # Optimisation GPU
```

#### Endpoints FastAPI

##### POST /transcribe
```python
# Paramètres
audio: UploadFile       # Fichier audio multipart
language: str = "fr"    # Langue de transcription

# Réponse
{
    "text": str,
    "processing_time": float,
    "filename": str
}
```

##### POST /whisper
```python
# Paramètres (JSON)
{
    "audio": str,           # Base64 encoded audio
    "filename": str,        # Nom du fichier
    "connection_id": str    # ID de connexion
}

# Réponse
{
    "transcription": str
}
```

#### Optimisations performance
- **Beam size** : 5 (compromis précision/vitesse)
- **Streaming** : Traitement via BytesIO
- **Fallback** : Fichier temporaire si BytesIO échoue
- **Cleanup** : Suppression automatique fichiers temp

### 2.6 Transformations audio (`transform_data.py`)

#### Fonctions de conversion

##### int2float()
```python
def int2float(sound):
    """Conversion int16 → float32 normalisé [-1,1]"""
    abs_max = np.abs(sound).max()
    sound = sound.astype('float32')
    if abs_max > 0:
        sound *= 1/32768  # Normalisation 16-bit
    return sound.squeeze()
```

##### slin16_to_pcm()
```python
def slin16_to_pcm(slin16_bytes):
    """Décodage SLIN16 (big-endian) → PCM int16"""
    return np.frombuffer(slin16_bytes, dtype='>i2').astype(np.int16)
```

##### tensor_to_wav_bytes()
```python
def tensor_to_wav_bytes(tensor, sample_rate=16000):
    """PyTorch tensor → fichier WAV en mémoire"""
    buffer = BytesIO()
    torchaudio.save(buffer, tensor.unsqueeze(0), sample_rate, format="wav")
    return buffer.read()
```

## 3. Flux de données

### 3.1 Appel entrant
```
1. Asterisk → StasisStart event
2. ARI Controller → answer() + welcome message
3. Canal snooping créé (spy="in") 
4. Canal enregistrement créé (spy="both")
5. External media + bridge RTP
6. RTP Receiver → écoute paquets audio
```

### 3.2 Traitement parole
```
1. RTP packets → décodage SLIN16
2. VAD analysis → détection parole/silence  
3. Buffering → accumulation segments
4. Whisper STT → transcription texte
5. Intent API → classification intention
6. Bot Manager → logique conversation
7. Audio response → lecture fichier son
```

### 3.3 Synchronisation état
```
Redis "bot_speaking" ←→ ARI Controller (playback events)
                     ←→ RTP Receiver (conditional processing)
```

## 4. Protocoles de communication

### 4.1 RTP (Real-time Transport Protocol)
- **Format** : SLIN16 (16-bit signed linear, big-endian)
- **Sample rate** : 16 kHz
- **Channels** : Mono
- **Packet size** : Variable (typiquement 320 bytes = 20ms audio)

### 4.2 ARI REST API
- **Base URL** : `http://91.134.37.11:8088`
- **Authentication** : HTTP Basic (myuser:mypassword)
- **WebSocket** : Events en temps réel
- **Endpoints utilisés** :
  - `POST /channels/{channelId}/answer`
  - `POST /channels/{channelId}/play`
  - `POST /channels/{channelId}/snoop`
  - `POST /channels/externalMedia`

### 4.3 APIs internes

#### Intent Detection API
```
POST http://91.134.37.11:8056/embedding_main/
Content-Type: application/json
{
    "sentence": "transcription text"
}

Response:
{
    "intent": "intention_detected"
}
```

## 5. Gestion des erreurs et robustesse

### 5.1 Stratégies de retry
- **API Intent** : Fallback vers FAQ si main échoue
- **Whisper** : Retry avec temp file si BytesIO échoue
- **Redis** : Fonctionnement dégradé si indisponible
- **RTP** : Timeout 1s avec traitement forcé

### 5.2 Gestion des états d'erreur
```python
# Bot Manager - Codes d'erreur
"request_timeout_error"    # Timeout API
"api_request_error"        # Erreur HTTP
"json_decode_error"        # Parsing JSON
"unknown_error"            # Autres exceptions
```

### 5.3 Nettoyage des ressources
- **Canaux** : Destruction automatique via StasisEnd
- **Bridges** : Nettoyage lors fermeture canaux
- **Fichiers temp** : Suppression automatique
- **Connexions** : Fermeture propre Redis/ARI

## 6. Monitoring et observabilité

### 6.1 Logs structurés
```python
# Format standard
'%(asctime)s - %(name)s - %(levelname)s - %(message)s'

# Niveaux utilisés
INFO:  États conversation, événements système
ERROR: Échecs API, erreurs traitement
DEBUG: Détails techniques, data flows
```

### 6.2 Métriques surveillées
- **Canaux actifs** par type (principal/snooping/media)
- **Temps de traitement** Whisper
- **Taux de succès** APIs Intent
- **Distribution des intentions** détectées
- **Durée des conversations**

### 6.3 Health checks
```python
# Whisper service
GET /health → {"status": "ok", "model": "large-v3", "device": "cuda"}

# ARI Controller  
GET /channels → {"channels": [...]}

# RTP Receiver
# Logs + Redis connectivity check
```

## 7. Sécurité

### 7.1 Authentication
- **ARI** : HTTP Basic Authentication
- **APIs internes** : Pas d'auth (réseau privé)
- **Redis** : Pas d'auth (localhost)

### 7.2 Validation des données
- **Transcriptions** : Sanitization basique
- **Channel IDs** : Validation format Asterisk
- **Audio data** : Validation format/taille

### 7.3 Limitations débit
- **Whisper** : Pas de rate limiting explicite
- **Intent API** : Timeout 5s par requête
- **RTP** : Buffer max 32000 échantillons

## 8. Performance et scalabilité

### 8.1 Limitations actuelles
- **Mono-thread** : Un appel simultané maximum
- **Mémoire** : Buffers audio en RAM
- **GPU** : Un seul modèle Whisper chargé
- **Redis** : État non distribué

### 8.2 Optimisations implémentées
- **VAD** : Évite transcription silences
- **Buffering** : Contexte minimal requis
- **GPU** : Whisper sur CUDA si disponible
- **Streaming** : Audio processing en temps réel

### 8.3 Points d'amélioration
- **Multi-threading** : Appels parallèles
- **Load balancing** : Répartition Whisper
- **Persistance** : États en base de données
- **Monitoring** : Métriques Prometheus/Grafana

## 9. Déploiement et maintenance

### 9.1 Prérequis système
- **OS** : Linux (Ubuntu 20.04+ recommandé)
- **RAM** : 8GB minimum (16GB avec GPU)
- **GPU** : NVIDIA avec CUDA 11.8+ (optionnel)
- **Storage** : 10GB pour modèles + logs

### 9.2 Services externes
- **Asterisk** : Configuration ARI requise
- **Redis** : Instance locale ou distante
- **Intent API** : Service externe disponible

### 9.3 Maintenance
- **Logs rotation** : Logrotate recommandé
- **Modèles** : Mise à jour Whisper périodique
- **Monitoring** : Surveillance disque/mémoire
- **Backup** : États Redis si critique
