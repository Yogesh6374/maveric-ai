import os
import platform
import logging
from typing import Optional

logger = logging.getLogger("maveric_ai.image_qa")

# ── PIL ───────────────────────────────────────────────────────────────────────
try:
    from PIL import Image, ImageStat
    _PIL_AVAILABLE = True
except ImportError:
    Image = None
    _PIL_AVAILABLE = False

# ── Tesseract OCR (auto-detect path) ─────────────────────────────────────────
_TESSERACT_AVAILABLE = False
try:
    import pytesseract

    # Auto-detect Tesseract executable on different operating systems
    _os = platform.system()
    _candidate_paths = []

    if _os == "Windows":
        _candidate_paths = [
            r"C:\Program Files\Tesseract-OCR\tesseract.exe",
            r"C:\Program Files (x86)\Tesseract-OCR\tesseract.exe",
            r"C:\Users\{}\AppData\Local\Programs\Tesseract-OCR\tesseract.exe".format(
                os.environ.get("USERNAME", "")
            ),
        ]
        # Also check env override
        env_path = os.environ.get("TESSERACT_CMD")
        if env_path:
            _candidate_paths.insert(0, env_path)

    elif _os == "Linux":
        _candidate_paths = [
            "/usr/bin/tesseract",
            "/usr/local/bin/tesseract",
        ]
    elif _os == "Darwin":  # macOS
        _candidate_paths = [
            "/usr/local/bin/tesseract",
            "/opt/homebrew/bin/tesseract",
        ]

    for _path in _candidate_paths:
        if os.path.isfile(_path):
            pytesseract.pytesseract.tesseract_cmd = _path
            _TESSERACT_AVAILABLE = True
            logger.info("Tesseract found at: %s", _path)
            break

    if not _TESSERACT_AVAILABLE:
        # Try calling it as a system command (might be in PATH)
        import subprocess
        try:
            result = subprocess.run(["tesseract", "--version"], capture_output=True, timeout=5)
            if result.returncode == 0:
                _TESSERACT_AVAILABLE = True
                logger.info("Tesseract found in system PATH")
        except (FileNotFoundError, subprocess.TimeoutExpired):
            pass

    if not _TESSERACT_AVAILABLE:
        logger.warning(
            "Tesseract OCR not found. Install it from https://github.com/tesseract-ocr/tesseract "
            "or set the TESSERACT_CMD environment variable. OCR will be unavailable."
        )

except ImportError:
    pytesseract = None
    logger.warning("pytesseract package not installed. Install with: pip install pytesseract")


# ============================================================
# COLOR ANALYSIS
# ============================================================

def get_image_color_description(img) -> str:
    """Analyzes dominant color spectrum of image using PIL ImageStat."""
    try:
        stat = ImageStat.Stat(img)
        if len(stat.mean) >= 3:
            r, g, b = stat.mean[:3]
            if r > 180 and g > 180 and b > 180:
                return "predominantly bright/white"
            elif r < 60 and g < 60 and b < 60:
                return "predominantly dark/black"
            elif r > g and r > b:
                return "warm/reddish tint"
            elif g > r and g > b:
                return "greenish tint"
            elif b > r and b > g:
                return "cool/bluish tint"
    except Exception:
        pass
    return "balanced color spectrum"


# ============================================================
# MAIN EXTRACTION FUNCTION
# ============================================================

def extract_text_from_image(image_path: str) -> str:
    """
    Extracts text from image via Tesseract OCR, or generates detailed visual
    metadata via PIL when OCR is unavailable.

    FIXED: Tesseract path is now auto-detected on Windows/Linux/macOS.
    Set TESSERACT_CMD environment variable for custom installations.
    """
    if not os.path.exists(image_path):
        return "[Error: Image file does not exist]"

    if not _PIL_AVAILABLE:
        return "[Error: Pillow package missing. Install with: pip install Pillow]"

    try:
        img = Image.open(image_path)
        width, height = img.size
        format_name = img.format or "Image"
        color_desc = get_image_color_description(img)
        file_size_kb = round(os.path.getsize(image_path) / 1024, 1)

        # Attempt OCR
        ocr_text = ""
        ocr_status = "unavailable"

        if pytesseract and _TESSERACT_AVAILABLE:
            try:
                ocr_text = pytesseract.image_to_string(img).strip()
                ocr_status = "success" if ocr_text else "no_text_found"
            except Exception as e:
                logger.warning("Tesseract OCR error: %s", e)
                ocr_status = "error"
        elif pytesseract and not _TESSERACT_AVAILABLE:
            ocr_status = "tesseract_not_installed"

        if ocr_text:
            return (
                f"Extracted Image Text (OCR):\n{ocr_text}\n\n"
                f"Image Properties: {format_name} ({width}x{height} px, {color_desc})"
            )

        # Fallback: PIL metadata description
        ocr_note = ""
        if ocr_status == "tesseract_not_installed":
            ocr_note = " [Note: Install Tesseract OCR for text extraction]"

        return (
            f"Image Properties: {format_name} format, resolution {width}x{height} pixels, "
            f"file size {file_size_kb} KB, visual appearance: {color_desc}.{ocr_note}"
        )

    except Exception as e:
        logger.error("Image analysis error: %s", e)
        return f"[Image Analysis Error: {str(e)}]"


def is_ocr_available() -> bool:
    """Returns True if Tesseract OCR is properly configured and available."""
    return _TESSERACT_AVAILABLE
