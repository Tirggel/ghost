import os
from PIL import Image, ImageDraw, ImageFont

channels = [
    ('whatsapp', '#25D366'),
    ('telegram', '#2AABEE'),
    ('discord', '#5865F2'),
    ('slack', '#E01E5A'),
    ('signal', '#3A76F0'),
    ('imessage', '#34C759'),
    ('msteams', '#6264A7'),
    ('nextcloudtalk', '#0082C9'),
    ('matrix', '#000000'),
    ('tlon', '#000000'),
    ('zalo', '#0068FF'),
    ('webchat', '#6C757D')
]

os.makedirs('app/assets/icons/channels', exist_ok=True)

for name, color_hex in channels:
    # Create 128x128 image with solid color
    img = Image.new('RGB', (128, 128), color=color_hex)
    draw = ImageDraw.Draw(img)
    
    # Draw a simple white circle or initial
    draw.ellipse((24, 24, 104, 104), fill=None, outline='white', width=8)
    
    # Simple text (the first letter)
    # Using generic default font, PIL might not have TrueType easily on this minimal system
    text = name[0].upper()
    try:
        font = ImageFont.truetype("/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf", 64)
    except IOError:
        font = ImageFont.load_default()
        
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    w, h = right - left, bottom - top
    draw.text(((128-w)/2, (128-h)/2 - top), text, fill="white", font=font)
    
    img.save(f'app/assets/icons/channels/{name}.png')
    print(f"Generated {name}.png")

