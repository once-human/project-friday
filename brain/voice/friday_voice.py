#!/usr/bin/env python3
"""Friday's ears and voice. Runs as a child of the Friday shell and talks JSON lines over stdio.

Pipeline
  mic (pw-record, 16 kHz mono) ─▶ wake: Vosk (Indian English) with a tiny grammar ("hey friday") ─▶ verify: Whisper
      ─▶ listen: Vosk partials for live text + RMS endpointing ─▶ final: Whisper (small.en) with your jargon
  reply text ─▶ Piper (local neural TTS) ─▶ pw-play

Everything runs locally. Audio never leaves the machine.

stdout events  {"ev": ready|unavailable|muted|wake|level|partial|transcribing|final|cancel|speaking|error, ...}
stdin commands listen [followup] | cancel | stop | mute | unmute | say <json> | say+ <json> | say-end | quit
"""
import collections
import json
import math
import os
import queue
import re
import shutil
import struct
import subprocess
import sys
import threading
import time
import wave

RATE = 16000
CHUNK = 1600                       # 100 ms of 16-bit mono
HOME = os.path.expanduser("~")
DATA = os.environ.get("FRIDAY_HOME", os.path.join(HOME, ".local/share/friday"))
VOICE_DIR = os.path.join(DATA, ".voice")
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.join(HOME, ".cache")), "friday")

# ---------------------------------------------------------------- settings (config.env exports these)
STT_MODEL = os.environ.get("FRIDAY_STT_MODEL", "small.en")
STT_DEVICE = os.environ.get("FRIDAY_STT_DEVICE", "auto")          # auto | cpu | cuda
WAKE_ON = os.environ.get("FRIDAY_WAKE", "on") != "off"
SPEAK_ON = os.environ.get("FRIDAY_SPEAK", "on") != "off"
PIPER_VOICE = os.environ.get("FRIDAY_PIPER_VOICE", "en_GB-jenny_dioco-medium")
SILENCE_END = float(os.environ.get("FRIDAY_SILENCE_END", "1.1"))  # seconds of quiet that end a request
PAUSE_SENTENCE = float(os.environ.get("FRIDAY_PAUSE_SENTENCE", "0.34"))  # breath after a full stop
PAUSE_COMMA = float(os.environ.get("FRIDAY_PAUSE_COMMA", "0.14"))        # beat after a comma
NO_SPEECH_TIMEOUT = 6.0
MAX_UTTERANCE = 25.0
MAX_GAIN = float(os.environ.get("FRIDAY_MAX_GAIN", "10"))       # software gain ceiling for quiet mics
DEBUG = os.environ.get("FRIDAY_VOICE_DEBUG", "") == "1"
WAKE_PHRASES = ["hey friday", "okay friday", "hi friday", "friday"]
HALLUCINATIONS = {"thank you", "thanks for watching", "you", "bye", "thank you so much", "thanks"}
WAKE_RE = re.compile(r"\b(hey|hi|okay|ok|hay)\W{0,2}\s*fri\s*-?\s*day\b(?!'?s)", re.I)
# Plain "Friday" counts when you're addressing it: at the start of what you say ("Friday, open Chrome",
# "Friday?"), not in the middle of a sentence ("see you Friday", "Friday's left" on a video).
ADDRESS_RE = re.compile(r"(?:^|[.!?…]\s+)\W*fri\s*-?\s*day\b(?!'?s)", re.I)
LEADING_WAKE_RE = re.compile(r"^\W*((hey|hi|okay|ok|hay)\W*\s*)?fri\s*-?\s*day\b(?!s)\W*", re.I)
# Words Whisper should expect from you. Biasing the decoder like this fixes most jargon errors.
VOCAB = os.environ.get("FRIDAY_VOCAB", (
    "Friday, Claude, Claude Code, Hyprland, Quickshell, illogical-impulse, Arch Linux, pacman, yay, "
    "PixelOS, OrangeFox, adb, fastboot, sideload, Redmi, POCO, GitHub, commit, push, repo, kitty, "
    "Chrome, YouTube, Fred again, Onkar"))


def emit(ev, **kw):
    kw["ev"] = ev
    try:
        sys.stdout.write(json.dumps(kw) + "\n")
        sys.stdout.flush()
    except BrokenPipeError:
        os._exit(0)


def log(*a):
    print("[friday-voice %s]" % time.strftime("%H:%M:%S"), *a, file=sys.stderr, flush=True)


def debug(*a):
    if DEBUG:
        log(*a)


def speechify(t):
    """Turn screen text into something that sounds natural out loud."""
    t = re.sub(r"\[\[(listen|end)\]\]", "", t, flags=re.I)                                         # Friday's hidden tags
    t = re.sub(r"https?://\S+", "the link", t)
    t = re.sub(r"(~|/home/\w+)?(/[\w.\-]+){2,}/?", lambda m: m.group(0).rstrip("/").split("/")[-1], t)   # paths -> last part
    t = re.sub(r"[\U0001F300-\U0001FAFF\u2600-\u27BF]", "", t)                                       # emoji
    for a, b in (("e.g.", "for example"), ("i.e.", "that is"), (" vs ", " versus "), ("&", " and "),
                 ("%", " percent"), ("—", ", "), ("–", " to "), ("...", "…"), (" w/ ", " with "), ("etc.", "and so on")):
        t = t.replace(a, b)
    t = re.sub(r"\s*\(([^)]*)\)", r", \1,", t)          # parentheses read as an aside
    t = re.sub(r"\s+([,.!?])", r"\1", t)
    t = re.sub(r",\s*([.!?])", r"\1", t).replace(",,", ",")
    return re.sub(r"\s+", " ", t).strip(" ,")


def rms(chunk):
    n = len(chunk) // 2
    if n == 0:
        return 0.0
    s = struct.unpack("<%dh" % n, chunk[: n * 2])
    return math.sqrt(sum(x * x for x in s) / n) / 32768.0


# ---------------------------------------------------------------- sounds (generated, so nothing to ship)
def chime(path, freqs, dur=0.09, gap=0.025, vol=0.22):
    if os.path.exists(path):
        return path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sr, frames = 44100, bytearray()
    for i, f in enumerate(freqs):
        n = int(sr * dur)
        for k in range(n):
            t = k / sr
            env = min(1.0, k / (sr * 0.008)) * math.exp(-5.5 * t / dur)      # soft attack, quick bloom-out
            v = vol * env * (math.sin(2 * math.pi * f * t) + 0.25 * math.sin(4 * math.pi * f * t))
            frames += struct.pack("<h", int(max(-1, min(1, v)) * 32767))
        if i < len(freqs) - 1:
            frames += b"\x00\x00" * int(sr * gap)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(bytes(frames))
    return path


def play(path):
    player = shutil.which("paplay") or shutil.which("pw-play") or shutil.which("aplay")
    if player and path:
        subprocess.Popen([player, path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def raw_player(rate):
    """A command that plays raw s16le mono PCM from stdin. pw-play alone expects a sound *file*."""
    if shutil.which("pacat"):
        return ["pacat", "--playback", "--format=s16le", "--rate=%d" % rate, "--channels=1",
                "--latency-msec=120", "--client-name=Friday", "--stream-name=Friday voice"]
    if shutil.which("pw-cat"):
        help_text = subprocess.run(["pw-cat", "--help"], capture_output=True, text=True).stdout
        if "--raw" in help_text:
            return ["pw-cat", "--playback", "--raw", "--format", "s16", "--rate", str(rate), "--channels", "1", "-"]
    if shutil.which("aplay"):
        return ["aplay", "-q", "-t", "raw", "-f", "S16_LE", "-r", str(rate), "-c", "1"]
    return None


# ---------------------------------------------------------------- microphone
class Mic:
    def __init__(self):
        self.q = queue.Queue(maxsize=200)
        self.proc = None
        self.thread = None

    def cmd(self):
        if shutil.which("pw-record"):
            return ["pw-record", "--rate", str(RATE), "--channels", "1", "--format", "s16", "-"]
        if shutil.which("parecord"):
            return ["parecord", "--raw", "--rate=%d" % RATE, "--channels=1", "--format=s16le"]
        return None

    def start(self):
        if self.proc and self.proc.poll() is None:
            return True
        c = self.cmd()
        if not c:
            return False
        self.proc = subprocess.Popen(c, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)
        self.thread = threading.Thread(target=self._pump, daemon=True)
        self.thread.start()
        return True

    def _pump(self):
        p, buf = self.proc, b""
        while p.poll() is None:
            data = p.stdout.read(CHUNK * 2 - len(buf))
            if not data:
                break
            buf += data
            if len(buf) >= CHUNK * 2:
                try:
                    self.q.put_nowait(buf)
                except queue.Full:
                    try:
                        self.q.get_nowait()
                    except queue.Empty:
                        pass
                    self.q.put_nowait(buf)
                buf = b""

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
        self.proc = None
        self.drain()

    def drain(self):
        while not self.q.empty():
            try:
                self.q.get_nowait()
            except queue.Empty:
                break

    def read(self, timeout=0.2):
        try:
            return self.q.get(timeout=timeout)
        except queue.Empty:
            return None


# ---------------------------------------------------------------- speech engines (all optional, all local)
class Engines:
    def __init__(self):
        self.vosk_model = None
        self.whisper = None
        self.piper = None
        self.piper_rate = 22050
        self.np = None
        self._lock = threading.Lock()
        self._load_lock = threading.Lock()
        self._piper_lock = threading.Lock()

    def load_core(self):
        try:
            import numpy  # noqa: F401
            self.np = numpy
        except Exception:
            self.np = None
        try:
            from vosk import Model, SetLogLevel
            SetLogLevel(-1)
            path = os.path.join(VOICE_DIR, "vosk")
            if os.path.isdir(path):
                self.vosk_model = Model(path)
        except Exception as e:
            log("vosk unavailable:", e)
        return self.vosk_model is not None

    def _device(self):
        if STT_DEVICE != "auto":
            return STT_DEVICE, ("float16" if STT_DEVICE == "cuda" else "int8")
        try:
            import ctranslate2
            if ctranslate2.get_cuda_device_count() > 0:
                return "cuda", "float16"
        except Exception:
            pass
        return "cpu", "int8"

    def load_whisper(self):
        with self._load_lock:
            self._load_whisper()

    def _load_whisper(self):
        if self.whisper is not None or self.np is None:
            return
        try:
            from faster_whisper import WhisperModel
            dev, ct = self._device()
            root = os.path.join(VOICE_DIR, "whisper")

            def load(name):
                # Use the copy friday-voice-setup downloaded without touching the network; only fetch if missing.
                try:
                    return WhisperModel(name, device=dev, compute_type=ct, download_root=root, local_files_only=True)
                except Exception:
                    return WhisperModel(name, device=dev, compute_type=ct, download_root=root)

            self.whisper = load(STT_MODEL)
            log("whisper ready:", STT_MODEL, dev, ct)
        except Exception as e:
            log("whisper unavailable:", e)

    def load_piper(self):
        with self._piper_lock:
            self._load_piper()

    def _load_piper(self):
        if self.piper is not None:
            return
        try:
            from piper import PiperVoice
            onnx = os.path.join(VOICE_DIR, "piper", PIPER_VOICE + ".onnx")
            if os.path.exists(onnx):
                self.piper = PiperVoice.load(onnx)
                with open(onnx + ".json") as f:
                    self.piper_rate = int(json.load(f).get("audio", {}).get("sample_rate", 22050))
        except Exception as e:
            log("piper unavailable:", e)

    def transcribe(self, pcm, quick=False, prompt=True, live=False):
        model = self.whisper
        if model is None or self.np is None or not pcm:
            return None
        audio = self.np.frombuffer(pcm, dtype=self.np.int16).astype(self.np.float32) / 32768.0
        peak = float(self.np.max(self.np.abs(audio))) if audio.size else 0.0
        if 0 < peak < 0.5:                                  # quiet mic: bring speech up to a healthy level
            audio *= min(MAX_GAIN, 0.5 / peak)
        with self._lock:
            segs, _ = model.transcribe(
                audio, language="en", beam_size=1 if (quick or live) else 5, vad_filter=False,
                initial_prompt="Hey Friday." if quick else (VOCAB if prompt else None),
                condition_on_previous_text=False, without_timestamps=True)
            text = " ".join(s.text.strip() for s in segs).strip()
        if text.lower().strip(" .!?,") in HALLUCINATIONS and len(pcm) < RATE * 2 * 2:
            return ""
        return text

    def synth(self, text):
        """Yield raw s16 mono audio chunks for text (works with piper-tts 1.2 and 1.3+)."""
        v = self.piper
        if v is None:
            return
        if hasattr(v, "synthesize_stream_raw"):           # piper-tts <= 1.2
            for b in v.synthesize_stream_raw(text):
                yield b
        else:                                              # piper-tts >= 1.3
            cfg = None
            try:
                from piper import SynthesisConfig
                cfg = SynthesisConfig(length_scale=float(os.environ.get("FRIDAY_SPEECH_PACE", "1.0")),
                                      noise_scale=0.6, noise_w_scale=0.85)
            except Exception:
                pass
            for ch in (v.synthesize(text, syn_config=cfg) if cfg else v.synthesize(text)):
                yield getattr(ch, "audio_int16_bytes", b"")


# ---------------------------------------------------------------- the assistant's voice loop
class Voice:
    IDLE, LISTEN, SPEAK, MUTED = "idle", "listening", "speaking", "muted"

    def __init__(self, engines, mic):
        self.e = engines
        self.mic = mic
        self.cmds = queue.Queue()
        self.wake_on = WAKE_ON
        self.state = self.MUTED if not WAKE_ON else self.IDLE
        self.ring = collections.deque(maxlen=int(2.6 * RATE / CHUNK))   # last ~2.6 s, for wake verification
        self.noise = 0.002                                                # adaptive noise floor (raw mic level)
        self.wake_rec = None
        self.cmd_rec = None
        self.speaker = None
        self.speak_stop = threading.Event()
        self.last_wake = 0.0
        self.last_check = 0.0
        self.levels = collections.deque(maxlen=60)    # last ~6 s of idle levels, for the noise floor
        self.raw_ring = collections.deque(maxlen=self.ring.maxlen)     # raw level of each chunk in the ring
        self.cand_peak = 0.0
        self.quiet = False                            # verifying a wake word without showing anything yet
        self.peak = 0.02
        self.sound_on = chime(os.path.join(CACHE, "listen-on.wav"), [660, 990])
        self.sound_off = chime(os.path.join(CACHE, "listen-off.wav"), [880, 587])
        self.sound_soft = chime(os.path.join(CACHE, "listen-soft.wav"), [784], dur=0.07, vol=0.11)   # "go on…"

    # ----- automatic gain: quiet mics get lifted so the recognizers can hear you
    def agc(self, chunk, learn=True):
        r = rms(chunk)
        if learn:
            self.peak = max(r, self.peak * 0.996)
        g = min(MAX_GAIN, max(1.0, 0.12 / max(self.peak, 0.004)))
        if g <= 1.05 or self.e.np is None:
            return chunk
        a = self.e.np.frombuffer(chunk, dtype=self.e.np.int16).astype(self.e.np.float32) * g
        self.e.np.clip(a, -32768, 32767, out=a)
        return a.astype(self.e.np.int16).tobytes()

    # ----- recognizers
    def new_wake_rec(self):
        from vosk import KaldiRecognizer
        r = KaldiRecognizer(self.e.vosk_model, RATE, json.dumps(WAKE_PHRASES + ["[unk]"]))
        r.SetWords(True)
        return r

    def new_cmd_rec(self):
        from vosk import KaldiRecognizer
        return KaldiRecognizer(self.e.vosk_model, RATE)

    # ----- commands from the shell
    def stdin_loop(self):
        for line in sys.stdin:
            self.cmds.put(line.rstrip("\n"))
        self.cmds.put("quit")

    def handle(self, c):
        if c.startswith("listen"):
            self.stop_speaking()
            self.begin_listen(chime_on=True, followup=c.endswith("followup"))
        elif c in ("cancel", "stop"):
            if self.state == self.LISTEN:
                self.state = self.IDLE if self.wake_on else self.MUTED
                emit("cancel")
                self.after_listen()
            self.stop_speaking()
        elif c == "mute":
            self.stop_speaking()
            self.wake_on = False
            self.state = self.MUTED
            self.mic.stop()
            emit("muted")
        elif c == "unmute":
            self.wake_on = True
            self.state = self.IDLE
            self.mic.start()
            emit("ready", wake=True)
        elif c.startswith("say+ "):           # append a sentence to what Friday is saying
            try:
                self.say_add(json.loads(c[5:]))
            except Exception:
                self.say_add(c[5:])
        elif c == "say-end":                   # that's everything for this answer
            self.say_end()
        elif c.startswith("say "):            # say this, now, instead of anything else
            try:
                text = json.loads(c[4:])
            except Exception:
                text = c[4:]
            self.speak(text)
        elif c == "quit":
            self.stop_speaking()
            self.mic.stop()
            sys.exit(0)

    # ----- listening
    def begin_listen(self, chime_on, followup=False, pending=False, quiet=False):
        if not self.mic.start():
            emit("error", msg="No microphone recorder found (install pipewire or pulseaudio-utils).")
            return
        self.state = self.LISTEN
        self.cmd_rec = self.new_cmd_rec()
        self.utt = bytearray()
        self.started = time.time()
        self.no_speech_timeout = 7.0 if followup else NO_SPEECH_TIMEOUT
        self.followup = followup
        self.pending = pending                  # wake not confirmed yet: listen, but quietly
        self.quiet = quiet                      # ...and don't even show the panel until it is
        self.listen_id = getattr(self, "listen_id", 0) + 1
        self.verify = None
        self.voiced = 0.0
        self.heard_at = None
        self.last_voice = None
        self.reset_partials()
        if chime_on and not quiet:
            play(self.sound_soft if followup else self.sound_on)
        if not quiet:
            emit("prewake" if pending else "wake")
        # Whisper loads lazily the first time you talk, then stays warm.
        threading.Thread(target=self.e.load_whisper, daemon=True).start()

    def after_listen(self):
        self.cmd_rec = None
        if self.wake_rec is not None:
            self.wake_rec.Reset()
        self.ring.clear()
        self.raw_ring.clear()
        if not self.wake_on or self.state == self.MUTED:
            self.mic.stop()             # wake word off: the mic is fully released between requests

    def on_listen_chunk(self, chunk, raw):
        now = time.time()
        # still confirming the wake word in the background?
        if self.pending:
            if self.verify is not None:
                ok, heard = self.verify
                if ok:
                    self.pending = False
                    self.last_wake = now
                    log("wake confirmed: %r (level %.4f, %.2fs after the word)" % (heard, self.cand_peak, now - self.started))
                    if self.quiet:
                        self.quiet = False
                        play(self.sound_on)
                    emit("wake")
                    if self.partial and self.clean(self.partial):
                        emit("partial", text=self.clean(self.partial))
                else:
                    log("wake rejected (heard %r, level %.4f%s)" % (heard, self.cand_peak, ", quiet" if self.quiet else ""))
                    self.state = self.IDLE if self.wake_on else self.MUTED
                    if not self.quiet:                   # nothing was shown for a quiet check: nothing to undo
                        emit("cancel", reason="false wake")
                    self.quiet = False
                    self.reset_partials()
                    self.after_listen()
                    return
            elif now - self.started > 6:            # verification hung: give up quietly
                self.verify = (False, "(timeout)")
        self.utt += chunk
        # Loudness is judged on the raw mic signal: the automatic gain moves around (Friday's own voice
        # pushes it down), so gated levels after it made follow-ups miss you.
        level = raw
        if len(self.levels) < 10:
            self.levels.append(raw)                  # no idle history yet (wake word off): learn the room here
            self.noise = sorted(self.levels)[len(self.levels) // 5]
        if not self.quiet:
            emit("level", v=round(min(1.0, level / max(self.noise * 8, 0.004)), 3))
        speech_floor = max(self.noise * 2.5, 0.002)
        loud = level > speech_floor
        if loud:
            self.last_voice = now
            if now - self.started > 0.4:            # skip the tail of "…Friday" itself
                self.voiced += CHUNK / RATE
        # live words: finished Vosk segments + the one in progress
        if self.cmd_rec.AcceptWaveform(bytes(chunk)):
            seg = json.loads(self.cmd_rec.Result()).get("text", "")
            if seg:
                self.said = (self.said + " " + seg).strip()
            cur = self.said
        else:
            cur = (self.said + " " + json.loads(self.cmd_rec.PartialResult()).get("partial", "")).strip()
        if cur and cur != self.partial:
            self.partial = cur
            if self.clean(cur) and (loud or not self.followup):
                self.last_voice = now               # new words are proof you're still talking
            if not self.pending and not self.roll_text:
                emit("partial", text=self.clean(cur))
        # every ~1.2 s, Whisper re-reads what you've said so far; its text replaces Vosk's rough guess
        if (not self.pending and not self.rolling and self.heard_at is not None and self.e.whisper is not None
                and now - self.last_roll > 1.2 and len(self.utt) > RATE * 2):
            self.rolling, self.last_roll = True, now
            threading.Thread(target=self._roll, args=(bytes(self.utt), self.listen_id), daemon=True).start()
        # "you're talking": real words from Vosk, or at least ~0.6 s of voice at a real speaking level
        if self.heard_at is None and self.last_voice and now - self.last_voice < 0.5 and (self.clean(cur) or self.voiced >= 0.6):
            self.heard_at = now
        if self.pending:
            return                                  # never end or send before the wake word is confirmed
        # end of request?
        if self.heard_at is None and now - self.started > self.no_speech_timeout:
            self.state = self.IDLE if self.wake_on else self.MUTED
            log("listening ended: no speech%s" % (" (follow-up)" if self.followup else ""))
            emit("cancel", reason="no speech", followup=self.followup)
            play(self.sound_off)
            self.reset_partials()
            self.after_listen()
            return
        quiet_for = now - (self.last_voice or now)
        if (self.heard_at is not None and quiet_for >= SILENCE_END) or now - self.started > MAX_UTTERANCE:
            self.finish()

    def reset_partials(self):
        self.partial = ""
        self.said = ""
        self.roll_text = ""
        self.rolling = False
        self.last_roll = time.time()

    def _roll(self, pcm, lid):
        try:
            t = self.clean(self.e.transcribe(pcm, live=True) or "")
        except Exception:
            t = ""
        if lid == self.listen_id and self.state == self.LISTEN and t:
            self.roll_text = t
            emit("partial", text=t + " …", accurate=True)
        self.rolling = False

    def finish(self):
        play(self.sound_off)
        emit("transcribing")
        pcm = bytes(self.utt)
        fallback = self.partial
        self.reset_partials()
        self.state = self.IDLE if self.wake_on else self.MUTED
        self.after_listen()
        text = None
        if self.e.whisper is None:
            self.e.load_whisper()
        try:
            text = self.e.transcribe(pcm)
        except Exception as e:
            log("whisper failed:", e)
        text = self.clean(text if text else fallback)
        if text:
            log("heard: %r" % text)
            emit("final", text=text)
        else:
            log("request dropped: nothing intelligible (vosk had %r)" % fallback)
            emit("cancel", reason="didn't catch that")

    @staticmethod
    def clean(t):
        t = (t or "").strip()
        t = LEADING_WAKE_RE.sub("", t).strip()
        if t and t[0].islower():
            t = t[0].upper() + t[1:]
        return t

    # ----- wake word
    def on_idle_chunk(self, chunk, raw):
        self.ring.append(chunk)
        self.raw_ring.append(raw)
        # noise floor = the quiet moments, not the average (a video or your own talking shouldn't raise it)
        self.levels.append(raw)
        if len(self.levels) >= 10:
            self.noise = sorted(self.levels)[len(self.levels) // 5]
        if self.wake_rec is None:
            self.wake_rec = self.new_wake_rec()
        hit, strong = False, False
        if self.wake_rec.AcceptWaveform(bytes(chunk)):
            res = json.loads(self.wake_rec.Result())
            txt = res.get("text", "")
            confs = [w.get("conf", 0) for w in res.get("result", []) if w.get("word") == "friday"]
            if txt and txt != "[unk]":
                debug("vosk final:", repr(txt), "conf", confs)
            if confs and any(p in txt for p in WAKE_PHRASES):
                hit, strong = True, max(confs) >= 0.85 or txt.strip().count(" ") >= 1
        else:
            p = json.loads(self.wake_rec.PartialResult()).get("partial", "")
            if any(ph in p for ph in WAKE_PHRASES):
                hit = True
                strong = any(ph in p for ph in WAKE_PHRASES[:3])     # "hey/okay/hi friday", not just "friday"
        now = time.time()
        if not hit or now - self.last_wake < 2.0 or now - self.last_check < 1.0:
            return
        self.wake_rec.Reset()
        self.last_check = now
        if self.e.whisper is None:
            return                                  # still warming up: never wake on a guess
        ring = b"".join(list(self.ring)[-20:])
        # Every candidate is checked by Whisper *before* anything shows: no panel, no chime, until it's
        # confirmed it was really you calling Friday. (Showing first and hiding on a miss made the panel
        # flash on videos and random talk.) Audio keeps buffering meanwhile, so "Friday, open Chrome" in
        # one breath still works.
        self.cand_peak = max(list(self.raw_ring)[-15:] or [raw])
        debug("candidate: strong=%s level %.4f noise %.4f -> checking" % (strong, self.cand_peak, self.noise))
        self.begin_listen(chime_on=True, pending=True, quiet=True)
        threading.Thread(target=self._verify, args=(ring,), daemon=True).start()

    def _verify(self, ring):
        try:
            heard = self.e.transcribe(ring, quick=True) or ""
        except Exception as e:
            heard = "(error %s)" % e
        self.verify = (bool(WAKE_RE.search(heard) or ADDRESS_RE.search(heard.strip())), heard)

    # ----- speaking: a stream of sentences, spoken as they arrive (Friday starts talking while it's still thinking)
    _END = object()

    def say_open(self):
        """Start (or keep) an utterance that sentences can be appended to."""
        if not SPEAK_ON:
            return False
        self.e.load_piper()
        if self.e.piper is None:
            return False
        if self.speaker and self.speaker.is_alive():
            return True
        self.speak_stop.clear()
        self.say_q = queue.Queue()
        self.speaker = threading.Thread(target=self._speak_stream, daemon=True)
        self.speaker.start()
        return True

    def say_add(self, text):
        text = (text or "").strip()
        if text and self.say_open():
            self.say_q.put(text)

    def say_end(self):
        if self.speaker and self.speaker.is_alive():
            self.say_q.put(self._END)

    def speak(self, text):                      # one-shot: replace whatever is being said
        self.stop_speaking()
        self.say_add(text)
        self.say_end()

    def _speak_stream(self):
        rate = self.e.piper_rate
        cmd = raw_player(rate)
        if not cmd:
            log("can't speak: no raw audio player (install libpulse for pacat, or alsa-utils for aplay)")
            emit("speaking", on=False)
            return
        p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=None)   # errors -> voice.log
        log("speaking via %s" % cmd[0])
        self.speak_proc = p
        prev = self.state
        if self.state != self.LISTEN:
            self.state = self.SPEAK
        emit("speaking", on=True)
        idx, written, t0, waited = 0, 0, None, 0.0
        timers = []
        try:
            while not self.speak_stop.is_set():
                try:
                    item = self.say_q.get(timeout=0.1)
                except queue.Empty:
                    waited += 0.1
                    if waited > 45:                 # the brain went quiet: don't hold the mic hostage
                        break
                    continue
                waited = 0.0
                if item is self._END:
                    break
                # One whole answer at a time: spoken clause by clause with real pauses, and every word lit up
                # at the moment you hear it.
                text = speechify(item)
                clauses = []                        # (clause text, pause after in seconds)
                for sent in re.split(r"(?<=[.!?…])\s+", text):
                    pieces = re.split(r"(?<=[,;:])\s+", sent.strip())
                    for k, piece in enumerate(pieces):
                        if piece:
                            last = k == len(pieces) - 1
                            clauses.append((piece, PAUSE_SENTENCE if last else PAUSE_COMMA))
                words = [w for c, _ in clauses for w in c.split()]
                emit("words", words=words, base=idx)
                for clause, pause in clauses:
                    if self.speak_stop.is_set():
                        break
                    audio = b"".join(self.e.synth(clause))
                    now = time.time()
                    if t0 is not None and now > t0 + written / rate:
                        t0 = now - written / rate   # playback ran dry while we waited: re-align the clock
                    if t0 is None:
                        t0 = now
                    dur = len(audio) / 2 / rate
                    cw = clause.split()
                    weights = [len(w) + 2 + (3 if w[-1:] in ",;:" else 0) for w in cw]
                    total = max(1, sum(weights))
                    offset = max(0.0, t0 + written / rate - now) + min(0.06, dur * 0.05)
                    for wgt in weights:
                        tm = threading.Timer(offset, emit, args=("word",), kwargs={"i": idx})
                        tm.daemon = True
                        tm.start()
                        timers.append(tm)
                        offset += dur * 0.95 * wgt / total
                        idx += 1
                    audio += b"\x00\x00" * int(rate * pause)
                    step = rate // 5 * 2            # write in 200 ms slices so "stop" is instant
                    for k in range(0, len(audio), step):
                        if self.speak_stop.is_set():
                            break
                        p.stdin.write(audio[k:k + step])
                        p.stdin.flush()
                    written += len(audio) // 2
            p.stdin.close()
            # wait until the last word has actually been heard (the player may exit before its buffer drains)
            end_at = (t0 or time.time()) + written / rate + 0.15
            while not self.speak_stop.is_set() and (p.poll() is None or time.time() < end_at):
                time.sleep(0.05)
        except (BrokenPipeError, OSError, ValueError) as e:
            log("speech output stopped:", e)
        except Exception as e:
            log("speech failed:", repr(e))
        finally:
            for tm in timers:
                tm.cancel()
            if p.poll() is None:
                p.terminate()
            if self.state == self.SPEAK:
                self.state = prev if prev != self.SPEAK else (self.IDLE if self.wake_on else self.MUTED)
            self.mic.drain()                    # don't hear ourselves
            self.ring.clear()
            self.raw_ring.clear()
            emit("speaking", on=False)

    def stop_speaking(self):
        if self.speaker and self.speaker.is_alive():
            self.speak_stop.set()
            p = getattr(self, "speak_proc", None)
            if p and p.poll() is None:
                p.terminate()
            self.speaker.join(timeout=1.0)

    # ----- main loop
    def run(self):
        threading.Thread(target=self.stdin_loop, daemon=True).start()
        if self.state == self.IDLE:
            if not self.mic.start():
                emit("unavailable", reason="No microphone recorder found (install pipewire or pulseaudio-utils).")
                return
            emit("ready", wake=True)
        else:
            emit("muted")
        # warm the models in the background so the first request is fast
        threading.Thread(target=lambda: (self.e.load_whisper(), self.e.load_piper()), daemon=True).start()
        while True:
            try:
                while True:
                    self.handle(self.cmds.get_nowait())
            except queue.Empty:
                pass
            if self.state in (self.MUTED,) and self.cmd_rec is None:
                time.sleep(0.1)
                continue
            chunk = self.mic.read(0.15)
            if chunk is None:
                continue
            if self.state == self.SPEAK:
                continue                    # drop audio so Friday doesn't wake itself (or turn its gain down)
            raw = rms(chunk)
            # the start of a listen is mostly our own chime: don't let it teach the gain control
            chunk = self.agc(chunk, learn=not (self.state == self.LISTEN and time.time() - self.started < 0.3))
            if self.state == self.LISTEN:
                self.on_listen_chunk(chunk, raw)
            elif self.state == self.IDLE:
                self.on_idle_chunk(chunk, raw)


# ---------------------------------------------------------------- one-shot test: record, transcribe, say it back
def selftest():
    e = Engines()
    ok = e.load_core()
    print("vosk model:", "ok" if ok else "MISSING")
    e.load_whisper()
    print("whisper:", "ok (%s)" % STT_MODEL if e.whisper else "MISSING")
    e.load_piper()
    print("piper voice:", "ok (%s)" % PIPER_VOICE if e.piper else "MISSING")
    m = Mic()
    if not m.start():
        print("microphone: no recorder (pw-record/parecord) found")
        return 1
    print("\nSay something for 5 seconds…")
    pcm, t0 = bytearray(), time.time()
    while time.time() - t0 < 5:
        c = m.read(0.3)
        if c:
            pcm += c
    m.stop()
    peak = max((rms(bytes(pcm[i:i + CHUNK * 2])) for i in range(0, len(pcm), CHUNK * 2)), default=0)
    vol = subprocess.run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@"], capture_output=True, text=True).stdout.strip() if shutil.which("wpctl") else "?"
    print("input level peak: %.3f %s   (mic volume: %s)" % (peak, "quiet: Friday boosts it in software" if peak < 0.05 else "", vol))
    t = time.time()
    text = e.transcribe(bytes(pcm))
    print("heard: %r  (%.2fs)" % (text, time.time() - t))
    if text and e.piper:
        v = Voice(e, m)
        v.speak("You said: " + text)
        v.speaker.join()
    return 0


def waketest():
    """Run the real wake loop for 45 s and show what it hears. Say "Hey Friday" a few times."""
    global DEBUG, emit
    DEBUG = True
    e = Engines()
    if not e.load_core():
        print("vosk model missing: run friday-voice-setup")
        return 1
    e.load_whisper()
    mic = Mic()
    if not mic.start():
        print("no recorder (pw-record/parecord)")
        return 1
    v = Voice(e, mic)
    v.state = v.IDLE
    shown = {"t": 0}

    def show(ev, **kw):
        if ev == "level":
            return
        print("\n  →", ev, kw if kw else "", flush=True)
        if ev == "wake":
            print("    (now say a request, e.g. 'what time is it')", flush=True)
    emit = show
    print("Listening for 45 s. Say \"Hey Friday\" a few times, at normal volume.\n")
    t0 = time.time()
    while time.time() - t0 < 45:
        c = mic.read(0.2)
        if c is None:
            continue
        raw = rms(c)
        c = v.agc(c)
        if time.time() - shown["t"] > 0.25:
            bar = "█" * int(min(40, rms(c) * 200))
            sys.stdout.write("\r  mic %.3f  gain x%.1f  %-40s" % (raw, min(MAX_GAIN, max(1.0, 0.12 / max(v.peak, 0.004))), bar))
            sys.stdout.flush()
            shown["t"] = time.time()
        if v.state == v.LISTEN:
            v.on_listen_chunk(c, raw)
        elif v.state == v.IDLE:
            v.on_idle_chunk(c, raw)
    mic.stop()
    print("\ndone")
    return 0


def main():
    emit("hello", v=5, pid=os.getpid())
    if "--test" in sys.argv:
        sys.exit(selftest())
    if "--wake-test" in sys.argv:
        sys.exit(waketest())
    e = Engines()
    if not e.load_core():
        emit("unavailable", reason="Voice isn't set up yet. Run friday-voice-setup.")
        # stay alive quietly so the shell doesn't restart-loop us
        for line in sys.stdin:
            if line.strip() == "quit":
                break
        return
    Voice(e, Mic()).run()


if __name__ == "__main__":
    main()
