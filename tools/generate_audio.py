import math, os, struct, wave

OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio')
os.makedirs(OUT, exist_ok=True)

def tone(path, notes, duration=0.22, volume=0.28, wave_type='sine'):
    rate = 22050
    frames = int(rate * duration)
    with wave.open(path, 'wb') as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(rate)
        data = bytearray()
        for i in range(frames):
            t = i / rate
            value = 0.0
            for freq, weight in notes:
                phase = 2 * math.pi * freq * t
                value += weight * (math.sin(phase) if wave_type == 'sine' else (1.0 if math.sin(phase) >= 0 else -1.0))
            env = min(1.0, i / (rate * 0.015)) * min(1.0, (frames - i) / (rate * 0.05))
            sample = int(max(-1.0, min(1.0, value * volume * env)) * 32767)
            data += struct.pack('<h', sample)
        f.writeframes(data)

tone(os.path.join(OUT, 'putt_hit.wav'), [(180, 0.55), (420, 0.25)], 0.12, 0.42, 'sine')
tone(os.path.join(OUT, 'ui_click.wav'), [(660, 0.45), (880, 0.2)], 0.08, 0.25, 'sine')
tone(os.path.join(OUT, 'cup_entry.wav'), [(523, 0.35), (659, 0.3), (784, 0.3)], 0.42, 0.32, 'sine')
tone(os.path.join(OUT, 'hazard_reset.wav'), [(130, 0.5), (95, 0.25)], 0.20, 0.24, 'sine')
print('generated', sorted(os.listdir(OUT)))
