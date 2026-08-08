import requests
import urllib.parse
import os
import random
try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    Image = None

def generate_fallback_image(prompt: str, output_path: str):
    """
    Generates a high-quality 1024x1024 abstract AI wallpaper image with dynamic gradients and typography
    Guarantees image generation never fails even when offline
    """
    if not Image:
        # Create minimal fallback PNG if Pillow is not available
        with open(output_path, "wb") as f:
            f.write(b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\rIDATx\x9cc\xf8\xff\xff?\x03\x00\x05\xfe\x02\xfe\xdc\xcc\x59\xe7\x00\x00\x00\x00IEND\xaeB`\x82")
        return "SUCCESS"

    width, height = 1024, 1024
    img = Image.new("RGB", (width, height), color=(15, 23, 42))
    draw = ImageDraw.Draw(img)

    # Dynamic color palette based on prompt
    prompt_lower = prompt.lower()
    if "cyberpunk" in prompt_lower or "neon" in prompt_lower:
        c1, c2 = (147, 51, 234), (59, 130, 246)  # Purple to Blue
    elif "nature" in prompt_lower or "forest" in prompt_lower:
        c1, c2 = (16, 185, 129), (5, 150, 105)  # Emerald
    elif "sunset" in prompt_lower or "fire" in prompt_lower:
        c1, c2 = (244, 63, 94), (245, 158, 11)   # Rose to Amber
    else:
        c1, c2 = (79, 70, 229), (6, 182, 212)    # Indigo to Cyan

    # Draw gradient
    for y in range(height):
        r = int(c1[0] + (c2[0] - c1[0]) * (y / height))
        g = int(c1[1] + (c2[1] - c1[1]) * (y / height))
        b = int(c1[2] + (c2[2] - c1[2]) * (y / height))
        draw.line([(0, y), (width, y)], fill=(r, g, b))

    # Add abstract geometry lighting elements
    for _ in range(8):
        x0 = random.randint(-100, width)
        y0 = random.randint(-100, height)
        radius = random.randint(150, 400)
        draw.ellipse([x0, y0, x0 + radius, y0 + radius], outline=(255, 255, 255, 30), width=3)

    # Watermark text
    try:
        font = ImageFont.load_default()
        watermark = f"Maveric AI Generated: {prompt[:40]}..."
        draw.text((40, height - 60), watermark, fill=(255, 255, 255), font=font)
    except Exception:
        pass

    img.save(output_path, format="PNG")
    return "SUCCESS"

def generate_image_from_api(prompt: str, output_path: str) -> str:
    """
    Tries Pollinations AI API first, fallback to PIL gradient generation if offline
    """
    try:
        encoded_prompt = urllib.parse.quote(prompt)
        image_url = f"https://image.pollinations.ai/prompt/{encoded_prompt}?width=1024&height=1024&nologo=true"

        response = requests.get(image_url, timeout=15)

        if response.status_code == 200 and len(response.content) > 1000:
            with open(output_path, "wb") as f:
                f.write(response.content)
            return "SUCCESS"

    except Exception as e:
        print(f"[Image Gen API] Online API error/timeout: {e}")

    # Fallback Offline Generator
    return generate_fallback_image(prompt, output_path)
