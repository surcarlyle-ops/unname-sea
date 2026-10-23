"""Extract the CC0 source PSD composite for the isolated preview."""
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[2]
folder = root / 'assets' / 'characters' / 'fps_arms' / 'reference'
image = Image.open(folder / 'Colour_Palette.psd').convert('RGB')
image.save(folder / 'Colour_Palette.png')
print(image.size)
