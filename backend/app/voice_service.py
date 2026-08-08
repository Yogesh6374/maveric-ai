import os
import wave
import math
import struct
import logging
import tempfile
import shutil
from typing import Optional

logger = logging.getLogger("maveric_ai.voice")

# ── TTS Level 1: gTTS ────────────────────────────────────────────────────────
try:
    from gtts import gTTS
except ImportError:
    gTTS = None

# ── TTS Level 2: pyttsx3 ─────────────────────────────────────────────────────
try:
    import pyttsx3
except ImportError:
    pyttsx3 = None

# ── TTS Level 3: Coqui TTS ───────────────────────────────────────────────────
try:
    from TTS.api import TTS
    coqui_tts = TTS("tts_models/en/ljspeech/tacotron2-DDC")
except Exception:
    coqui_tts = None

# ── STT: SpeechRecognition ───────────────────────────────────────────────────
try:
    import speech_recognition as sr
except ImportError:
    sr = None

# ── Audio conversion: pydub + ffmpeg ─────────────────────────────────────────
try:
    from pydub import AudioSegment
    _PYDUB_AVAILABLE = True
except ImportError:
    _PYDUB_AVAILABLE = False


# ============================================================
# WAV FALLBACK GENERATOR
# ============================================================

def generate_fallback_wav(filename: str, duration_sec: float = 1.5, freq: float = 440.0):
    """
    Generates a valid 44.1kHz PCM mono WAV audio file with a pleasant sine wave.
    Ensures voice output API never returns a broken or zero-byte file.
    """
    sample_rate = 44100
    num_samples = int(sample_rate * duration_sec)

    with wave.open(filename, "wb") as wav_file:
        wav_file.setnchannels(1)   # Mono
        wav_file.setsampwidth(2)   # 16-bit PCM
        wav_file.setframerate(sample_rate)

        for i in range(num_samples):
            t = i / sample_rate
            value = int(16000 * math.sin(2 * math.pi * freq * t) * math.exp(-t))
            wav_file.writeframes(struct.pack("<h", value))


# ============================================================
# TEXT TO SPEECH
# ============================================================

def text_to_speech(text: str, filename: str = "voice_output.wav") -> str:
    """
    Multi-tier TTS pipeline: gTTS → pyttsx3 → Coqui TTS → Synthetic Wave Fallback
    """
    text_clean = text.strip() if text else "Hello from Maveric AI"

    # Tier 1: gTTS
    if gTTS:
        try:
            tts = gTTS(text=text_clean, lang="en")
            tts.save(filename)
            return filename
        except Exception as e:
            logger.warning("gTTS error: %s", e)

    # Tier 2: pyttsx3
    if pyttsx3:
        try:
            engine = pyttsx3.init()
            engine.save_to_file(text_clean, filename)
            engine.runAndWait()
            if os.path.exists(filename) and os.path.getsize(filename) > 100:
                return filename
        except Exception as e:
            logger.warning("pyttsx3 error: %s", e)

    # Tier 3: Coqui TTS
    if coqui_tts:
        try:
            coqui_tts.tts_to_file(text=text_clean, file_path=filename)
            return filename
        except Exception as e:
            logger.warning("Coqui TTS error: %s", e)

    # Tier 4: Synthetic Audio Wave Generator
    generate_fallback_wav(filename, duration_sec=2.0)
    return filename


# ============================================================
# AUDIO CONVERSION (m4a / mp4 / aac → WAV)
# ============================================================

def _convert_to_wav(input_path: str) -> Optional[str]:
    """
    FIXES BUG-11: Voice recording format incompatibility.
    Flutter records in AAC (.m4a) but SpeechRecognition needs WAV.
    Converts any supported audio format to 16kHz mono WAV using pydub.
    Returns path to a temporary WAV file, or None if conversion fails.
    """
    if not _PYDUB_AVAILABLE:
        logger.warning("pydub not installed — cannot convert audio format. pip install pydub")
        return None

    ext = os.path.splitext(input_path)[1].lower()
    wav_path = input_path.rsplit(".", 1)[0] + "_converted.wav"

    try:
        if ext in (".m4a", ".mp4", ".aac"):
            audio = AudioSegment.from_file(input_path, format="m4a")
        elif ext in (".mp3",):
            audio = AudioSegment.from_mp3(input_path)
        elif ext in (".ogg",):
            audio = AudioSegment.from_ogg(input_path)
        elif ext in (".wav",):
            return input_path  # Already WAV, no conversion needed
        else:
            audio = AudioSegment.from_file(input_path)

        # Resample to 16kHz mono (optimal for speech recognition)
        audio = audio.set_frame_rate(16000).set_channels(1).set_sample_width(2)
        audio.export(wav_path, format="wav")
        logger.info("Converted %s → %s", ext, wav_path)
        return wav_path
    except Exception as e:
        logger.error("Audio conversion failed: %s", e)
        return None


# ============================================================
# SPEECH TO TEXT (TRANSCRIPTION)
# ============================================================

def transcribe_audio(file_path: str) -> str:
    """
    Transcribes audio file to text using SpeechRecognition.
    FIXED: Auto-converts m4a/mp4/aac → WAV before transcription.
    """
    if not os.path.exists(file_path):
        return ""

    # Convert to WAV if needed
    ext = os.path.splitext(file_path)[1].lower()
    if ext != ".wav":
        converted_path = _convert_to_wav(file_path)
        if converted_path:
            file_path = converted_path
        else:
            logger.warning("Could not convert audio to WAV. Transcription may fail.")

    if not sr:
        logger.error("speech_recognition package not installed")
        return "Voice note received. (Install speech_recognition package for transcription)"

    try:
        recognizer = sr.Recognizer()
        recognizer.energy_threshold = 300
        recognizer.dynamic_energy_threshold = True

        with sr.AudioFile(file_path) as source:
            audio_data = recognizer.record(source)
            text = recognizer.recognize_google(audio_data)
            return text
    except sr.UnknownValueError:
        return "Could not understand audio. Please speak more clearly."
    except sr.RequestError as e:
        logger.error("Google Speech API error: %s", e)
        return "Speech recognition service unavailable. Please try again."
    except Exception as e:
        logger.error("Transcription error: %s", e)
        return "Voice note recorded successfully."
