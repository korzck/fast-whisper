"""Gemma/MLX correction, prompt caching and safe fallback."""
from __future__ import annotations
from .models import LLM_REPO
from .prompts import SYSTEM_PROMPTS
from .protocol import stage
from .guard import clean_output, guard

class LLM:
    def load(self, glossary: str, language: str):
        self.glossary = glossary
        stage("Импорт MLX", 0.05)
        from huggingface_hub import snapshot_download
        from mlx_lm import load
        from mlx_lm.sample_utils import make_sampler
        stage("Загрузка весов Gemma 3 4B в память", 0.15)
        self.model, self.tok = load(snapshot_download(LLM_REPO))
        self.sampler = make_sampler(temp=0.0)
        self._set_language(language)
        stage("Прогрев: пробная генерация", 0.75)
        self._generate(self._ids("test one two three", ""), None, 8)
        stage("Кеш системного промпта", 0.9)
        self._build_prefix_cache()

    def _set_language(self, language: str):
        self.language = language if language in SYSTEM_PROMPTS else "en"
        self.system = SYSTEM_PROMPTS[self.language].format(glossary=self.glossary)

    def _ids(self, text: str, context: str) -> list[int]:
        user = (f"<context>{context}</context>\n" if context else "") + f"<text>{text}</text>"
        r = self.tok.apply_chat_template(
            [{"role": "system", "content": self.system}, {"role": "user", "content": user}],
            add_generation_prompt=True, tokenize=True)
        if hasattr(r, "keys"):
            r = r["input_ids"]
        return list(r)

    def _build_prefix_cache(self):
        from mlx_lm.models.cache import can_trim_prompt_cache, make_prompt_cache
        a, b = self._ids("Первый пример", ""), self._ids("совсем другой 123", "")
        n = 0
        while n < min(len(a), len(b)) and a[n] == b[n]:
            n += 1
        self.prefix_ids, self.cache = a[:n], make_prompt_cache(self.model)
        if not can_trim_prompt_cache(self.cache):
            self.cache = None
            return
        self._fill(self.prefix_ids)

    def _fill(self, ids):
        from mlx_lm.models.cache import trim_prompt_cache
        self._generate(ids, self.cache, 1)
        trim_prompt_cache(self.cache, self.cache[0].offset - len(self.prefix_ids))

    def _generate(self, ids, cache, max_tokens) -> str:
        from mlx_lm import stream_generate
        out = ""
        for r in stream_generate(self.model, self.tok, ids, max_tokens=max_tokens,
                                 sampler=self.sampler, prompt_cache=cache):
            out += r.text
            if "</text>" in out or "\n\n" in out.strip():
                break
        return out

    def correct(self, text: str, context: str, language: str | None = None) -> str:
        from mlx_lm.models.cache import trim_prompt_cache
        if language and language != self.language:
            # A language change alters the system prompt, so rebuild the prefix cache.
            self._set_language(language)
            self._build_prefix_cache()
        ids = self._ids(text, context)
        max_tokens = int(len(self.tok.encode(text)) * 1.6) + 24
        if self.cache is None:
            out = self._generate(ids, None, max_tokens)
        else:
            p = self.prefix_ids
            n = min(len(p), len(ids) - 1)
            k = next((j for j in range(n) if ids[j] != p[j]), n)
            if k < len(p):
                trim_prompt_cache(self.cache, self.cache[0].offset - k)
            out = self._generate(ids[k:], self.cache, max_tokens)
            trim_prompt_cache(self.cache, self.cache[0].offset - k)
            if k < len(p):
                self._fill(p[k:])
        out = clean_output(out)
        ok, _ = guard(text, out)
        return out if ok else text
