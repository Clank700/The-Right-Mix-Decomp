#!/usr/bin/env python
"""build_assets.py <bartender.swf> <out_assets_dir>

Writes <out>/game.json (shapes, fonts, text, buttons, sprite timelines, exports) and extracts the bitmaps
and sounds (extract_media.py, no external decompiler) into <out>/images and <out>/sounds (sounds become trimmed 16-bit WAV, see convert_sounds).
"""
import array
import json
import os
import shutil
import subprocess
import sys
import tempfile
import wave

import extract_media
import mp3tool_build
import swfparse
import swfio


HERE = os.path.dirname(os.path.abspath(__file__))


def decode_mp3(path):
    """MP3 -> (sample rate, list of signed 16-bit mono samples) using miniaudio via bin/mp3tool.exe."""
    MP3TOOL = mp3tool_build.ensure()
    with tempfile.TemporaryDirectory() as tmp:
        raw = os.path.join(tmp, 'a.raw')
        rate, _ = subprocess.check_output([MP3TOOL, path, raw]).split()
        pcm = array.array('h')
        with open(raw, 'rb') as f:
            pcm.frombytes(f.read())
        return int(rate), pcm


def write_wav(path, rate, channels, samples):
    with wave.open(path, 'wb') as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(samples.tobytes())


def bake_envelope(rate, pcm, env):
    """Apply a SWF sound envelope (points of [pos @ 44.1 kHz, left, right], levels 0..32768, linear between points).
    Returns (channels, samples): stereo when the points pan, otherwise mono."""
    pts = sorted(env)
    stereo = any(l != r for _, l, r in pts)

    def gain(t44, ch):
        if t44 <= pts[0][0]:
            return pts[0][1 + ch] / 32768
        for (p0, l0, r0), (p1, l1, r1) in zip(pts, pts[1:]):
            if t44 <= p1:
                a = (t44 - p0) / max(1, p1 - p0)
                v0, v1 = (l0, l1) if ch == 0 else (r0, r1)
                return (v0 + (v1 - v0) * a) / 32768
        return pts[-1][1 + ch] / 32768

    out = array.array('h')
    for i, x in enumerate(pcm):
        t44 = i * 44100 / rate
        if stereo:
            out.append(int(x * gain(t44, 0)))
            out.append(int(x * gain(t44, 1)))
        else:
            out.append(int(x * gain(t44, 0)))
    return (2 if stereo else 1), out


def convert_sounds(chars, main_frames, media_dir, snd_out):
    """MP3 (as extracted by extract_media.py) -> trimmed 16-bit WAV, one per sound, plus one baked variant per distinct envelope.

    Why: Flash skips the MP3 encoder delay ("SeekSamples", 1661 samples = 150 ms at 11 kHz) at the start of every
    sound; players that just decode the MP3 (MediaPlayer, miniaudio) play that silence, so sounds were late by 150 ms and
    loops had a gap. Cues with a volume envelope (fades) also lost the fade. Both are done here, once, at build time."""
    decoded = {}
    for fn in os.listdir(os.path.join(media_dir, 'sounds')):
        stem, ext = os.path.splitext(fn)
        cid = int(stem.split('_')[0])
        if cid < 0:
            continue
        rate, pcm = decode_mp3(os.path.join(media_dir, 'sounds', fn))
        pcm = pcm[max(0, chars[cid].get('seek', 0)):]
        decoded[cid] = (rate, pcm)
        write_wav(os.path.join(snd_out, '%d.wav' % cid), rate, 1, pcm)
        chars[cid]['file'] = 'sounds/%d.wav' % cid
    variants = {}
    timelines = [main_frames] + [c['frames'] for c in chars.values() if c.get('k') == 'sprite']
    for frames in timelines:
        for fr in frames:
            for cue in fr.get('snd', []):
                env = cue.pop('env', None)
                if not env or cue['id'] not in decoded:
                    continue
                key = (cue['id'], json.dumps(env))
                if key not in variants:
                    rate, pcm = decoded[cue['id']]
                    ch, out = bake_envelope(rate, pcm, env)
                    name = 'sounds/%d_e%d.wav' % (cue['id'], len([v for v in variants if v[0] == cue['id']]) + 1)
                    write_wav(os.path.join(os.path.dirname(snd_out), name), rate, ch, out)
                    variants[key] = name
                cue['f'] = variants[key]
    print('sounds: %d trimmed WAV + %d envelope variants' % (len(decoded), len(variants)))


def main(swf_path, out_dir):
    swf = swfio.Swf.load(swf_path)
    chars, exports, main_frames = swfparse.parse_all(swf)
    media_dir = tempfile.mkdtemp(prefix='rightmix_media_')
    extract_media.extract(swf_path, media_dir)
    os.makedirs(out_dir, exist_ok=True)
    img_out = os.path.join(out_dir, 'images')
    snd_out = os.path.join(out_dir, 'sounds')
    for d in (img_out, snd_out):
        shutil.rmtree(d, ignore_errors=True)
        os.makedirs(d)

    for fn in os.listdir(os.path.join(media_dir, 'images')):
        cid, ext = os.path.splitext(fn)
        shutil.copy(os.path.join(media_dir, 'images', fn), os.path.join(img_out, fn))
        chars[int(cid)]['file'] = 'images/' + fn
    convert_sounds(chars, main_frames, media_dir, snd_out)

    # fonts: only keep what text rendering needs
    doc = {
        'stage': {'w': 600, 'h': 440, 'fps': 18},
        'exports': exports,
        'chars': {str(k): v for k, v in sorted(chars.items())},
        'main': main_frames,
    }
    path = os.path.join(out_dir, 'game.json')
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(doc, f, separators=(',', ':'))
    kinds = {}
    for v in chars.values():
        kinds[v['k']] = kinds.get(v['k'], 0) + 1
    print('wrote', path, os.path.getsize(path), 'bytes;', kinds)


if __name__ == '__main__':
    main(*sys.argv[1:3])
