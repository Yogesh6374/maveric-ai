import os

# PyPDF2 / pypdf fallback
try:
    import PyPDF2
except ImportError:
    try:
        import pypdf as PyPDF2
    except ImportError:
        PyPDF2 = None

# python-docx fallback
try:
    import docx
except ImportError:
    docx = None

# pandas fallback
try:
    import pandas as pd
except ImportError:
    pd = None

# OCR image extraction fallback
from app.image_qa_service import extract_text_from_image

def extract_text_from_document(file_path: str) -> str:
    """
    Unified extraction pipeline for PDF, DOCX, TXT, CSV, and OCR Images (PNG, JPG, JPEG, WEBP)
    """
    if not os.path.exists(file_path):
        return ""

    file_lower = file_path.lower()

    # -------- PDF FILE --------
    if file_lower.endswith(".pdf"):
        if not PyPDF2:
            return "[Error: PyPDF2/pypdf package missing]"
        try:
            text = ""
            with open(file_path, "rb") as f:
                reader = PyPDF2.PdfReader(f)
                for page in reader.pages:
                    page_text = page.extract_text()
                    if page_text:
                        text += page_text + "\n"
            return text.strip()
        except Exception as e:
            return f"[PDF Extraction Error: {e}]"

    # -------- DOCX FILE --------
    if file_lower.endswith(".docx") or file_lower.endswith(".doc"):
        if not docx:
            return "[Error: python-docx package missing]"
        try:
            doc = docx.Document(file_path)
            full_text = [p.text for p in doc.paragraphs if p.text.strip()]
            return "\n".join(full_text)
        except Exception as e:
            return f"[DOCX Extraction Error: {e}]"

    # -------- CSV FILE --------
    if file_lower.endswith(".csv"):
        try:
            if pd:
                df = pd.read_csv(file_path)
                return df.to_string(index=False)
            else:
                with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
                    return f.read()
        except Exception as e:
            return f"[CSV Extraction Error: {e}]"

    # -------- IMAGE OCR (PNG, JPG, JPEG, WEBP) --------
    if any(file_lower.endswith(ext) for ext in [".png", ".jpg", ".jpeg", ".webp"]):
        try:
            ocr_text = extract_text_from_image(file_path)
            if ocr_text:
                return ocr_text
            return "[OCR: No text detected in image]"
        except Exception as e:
            return f"[OCR Extraction Error: {e}]"

    # -------- TXT & CODE FILES (Default Fallback) --------
    try:
        with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
            return f.read().strip()
    except Exception as e:
        return f"[File Extraction Error: {e}]"
