import os
import requests
from typing import Optional, Tuple

OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434").rstrip("/")
OLLAMA_API_KEY = os.getenv("OLLAMA_API_KEY", "")
TEXT_MODEL = os.getenv("TEXT_MODEL", "").strip()
VISION_MODEL = os.getenv("VISION_MODEL", "").strip()
TEXT_TIMEOUT = int(os.getenv("TEXT_TIMEOUT", "60"))
VISION_TIMEOUT = int(os.getenv("VISION_TIMEOUT", "300"))


def _ollama_headers() -> dict:
    if OLLAMA_API_KEY:
        return {"Authorization": f"Bearer {OLLAMA_API_KEY}"}
    return {}

# Priority list for dynamic model detection
MODEL_PRIORITY = [
    "qwen3",
    "qwen3.5",
    "qwen3:30b",
    "qwen3:8b",
    "gemma3",
    "llama3.3",
    "mistral",
    "llama3",
]

def get_installed_ollama_models() -> list:
    """
    Fetch all installed model tags from local Ollama instance
    """
    try:
        response = requests.get(
            f"{OLLAMA_BASE_URL}/api/tags",
            headers=_ollama_headers(),
            timeout=3,
        )
        if response.status_code == 200:
            data = response.json()
            models = [m.get("name") for m in data.get("models", []) if m.get("name")]
            return models
    except Exception as e:
        print(f"[Ollama Detection] Warning: Could not query Ollama tags at {OLLAMA_BASE_URL}: {e}")
    return []

def select_best_model() -> str:
    """
    Auto-detect installed model matching priority order, fallback to first available
    """
    if TEXT_MODEL:
        return TEXT_MODEL

    installed = get_installed_ollama_models()
    if "qwen3:latest" in installed:
        return "qwen3:latest"
    elif not installed:
        return "qwen3:latest"  # Default configuration target

    # Match in priority order
    for target in MODEL_PRIORITY:
        for installed_name in installed:
            if target.lower() in installed_name.lower():
                return installed_name

    # Return first available model if no priority target matched
    return installed[0]

def select_vision_model() -> str:
    """
    Auto-detect vision model
    """
    if VISION_MODEL:
        return VISION_MODEL

    installed = get_installed_ollama_models()
    if "qwen2.5vl:latest" in installed:
        return "qwen2.5vl:latest"
    elif not installed:
        return "qwen2.5vl:latest"

    for target in ["qwen2.5vl:latest", "llava"]:
        for installed_name in installed:
            if target.lower() in installed_name.lower():
                return installed_name

    return installed[0]

def is_reasoning_task(prompt: str) -> bool:
    """
    Detect if prompt requires step-by-step reasoning (Coding, Debugging, Math, Planning)
    """
    keywords = [
        "code", "coding", "python", "flutter", "dart", "java", "c++", "sql", "html", "css",
        "debug", "error", "exception", "fix", "bug", "traceback",
        "math", "calculate", "equation", "solve", "formula",
        "plan", "step-by-step", "architecture", "algorithm", "design"
    ]
    prompt_lower = prompt.lower()
    return any(k in prompt_lower for k in keywords)

def generate_text(prompt: str, system_prompt: Optional[str] = None, model: Optional[str] = None, image_base64: Optional[str] = None) -> Tuple[str, str]:
    """
    Generate text using Ollama with dynamic model selection and task mode logic
    Returns tuple of (response_text, model_used)
    """
    if image_base64:
        selected_model = model or select_vision_model()
    else:
        selected_model = model or select_best_model()
    is_reasoning = is_reasoning_task(prompt)

    if not system_prompt:
        if is_reasoning:
            system_prompt = (
                "You are Maveric AI in Reasoning Mode. Provide detailed, step-by-step, "
                "logical explanations, well-formatted code blocks, and precise answers."
            )
        else:
            system_prompt = (
                "You are Maveric AI. Provide clear, fast, direct, and concise answers."
            )

    full_prompt = f"System: {system_prompt}\nUser: {prompt}"

    try:
        url = f"{OLLAMA_BASE_URL}/api/generate"
        payload = {
            "model": selected_model,
            "prompt": full_prompt,
            "stream": False
        }
        
        if image_base64:
            payload["images"] = [image_base64]

        timeout = VISION_TIMEOUT if image_base64 else TEXT_TIMEOUT
        response = requests.post(url, json=payload, headers=_ollama_headers(), timeout=timeout)

        if response.status_code == 200:
            reply = response.json().get("response", "").strip()
            return reply, selected_model
        else:
            return f"[Ollama Error {response.status_code}: Unable to generate response]", selected_model

    except requests.exceptions.ConnectionError:
        return (
            f"[Service Unavailable: Ollama AI service is not reachable at {OLLAMA_BASE_URL}. "
            f"Start Ollama locally or configure OLLAMA_BASE_URL and OLLAMA_API_KEY for cloud.]",
            selected_model
        )
    except Exception as e:
        return f"[AI Generation Error: {str(e)}]", selected_model
