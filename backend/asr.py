"""Whisper/Core ML and GigaAM recognition adapters."""
from __future__ import annotations
import os
from .models import WHISPER_PATH as ASR_MODEL_FILE, ensure_whisper
from .protocol import stage

class ASR:
    def load(self, glossary: str, language: str, engine: str = "whisper"):
        self.engine = engine
        if engine == "gigaam":
            return self._load_gigaam()
        import numpy as np
        self.language = language
        stage("Импорт whisper.cpp", 0.05)
        from pywhispercpp.model import Model
        if not ASR_MODEL_FILE.exists():
            stage("Подготовка файлов модели", 0.1)
            os.environ["HF_HUB_OFFLINE"] = "0"
            ensure_whisper()
        stage("Загрузка весов и энкодера Core ML (первый раз — компиляция под Neural Engine)", 0.2)
        self.model = Model(
            str(ASR_MODEL_FILE), n_threads=4, redirect_whispercpp_logs_to=None,
            language=language, no_timestamps=True, print_progress=False, print_realtime=False,
            print_timestamps=False, initial_prompt=glossary, temperature=0.0, temperature_inc=0.0,
            no_speech_thold=0.6, suppress_blank=True,
        )
        stage("Прогрев: пробный прогон (компиляция шейдеров Metal)", 0.8)
        self.model.transcribe(np.zeros(16000, dtype=np.float32))

    # Common Whisper hallucinations on silence/noise, originating from training subtitles.
    _HALLUCINATIONS = ("продолжение следует", "субтитры", "спасибо за просмотр",
                       "редактор субтитров", "подписывайтесь на канал",
                       "thank you for watching", "thanks for watching", "subtitles by",
                       "please subscribe", "amara.org")

    def _load_gigaam(self):
        """GigaAM-v3: Russian CTC with punctuation and casing, ONNX int8.
        Use CPU: partial Core ML graph support makes repeated CPU/GPU transfers
        slower than CPU-only execution in local benchmarks."""
        import numpy as np
        stage("Импорт onnx-asr", 0.05)
        import onnx_asr
        stage("Загрузка GigaAM-v3 (int8, CPU)", 0.2)
        try:
            self.model = onnx_asr.load_model("gigaam-v3-e2e-ctc", quantization="int8",
                                             providers=["CPUExecutionProvider"])
        except Exception:
            # Model missing from cache: download it once (about 230 MB).
            stage("Скачивание GigaAM-v3 (~230 МБ, один раз)", 0.25)
            os.environ["HF_HUB_OFFLINE"] = "0"
            self.model = onnx_asr.load_model("gigaam-v3-e2e-ctc", quantization="int8",
                                             providers=["CPUExecutionProvider"])
        stage("Прогрев", 0.85)
        self.model.recognize(np.zeros(16000, dtype=np.float32))

    def transcribe(self, path: str, language: str | None = None) -> str:
        """Accept language per request to switch without reloading the model."""
        import soundfile as sf
        audio, _ = sf.read(path, dtype="float32")
        if self.engine == "gigaam":
            # GigaAM supports Russian only and ignores the selected language.
            return self.model.recognize(audio).strip()
        segs = self.model.transcribe(audio, language=language or self.language)
        text = " ".join(s.text.strip() for s in segs).strip()
        low = text.lower()
        if len(low) < 60 and any(h in low for h in self._HALLUCINATIONS):
            return ""
        return text
