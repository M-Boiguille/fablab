#!/usr/bin/env python3
import logging
import os
import time
from typing import List, Optional

import requests

logger = logging.getLogger(__name__)


class LLMClient:
    DEFAULT_GEMINI_URL = (
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
    )
    DEFAULT_DEEPSEEK_URL = "https://api.deepseek.com/v1/chat/completions"

    def __init__(
        self,
        gemini_key: Optional[str] = None,
        deepseek_key: Optional[str] = None,
        gemini_url: Optional[str] = None,
        deepseek_url: Optional[str] = None,
        max_retries: int = 3,
        backoff: int = 2,
    ):
        self.gemini_key = (gemini_key or os.environ.get("GEMINI_API_KEY") or "").strip()
        self.deepseek_key = (deepseek_key or os.environ.get("DEEPSEEK_API_KEY") or "").strip()
        self.gemini_url = gemini_url or self.DEFAULT_GEMINI_URL
        self.deepseek_url = deepseek_url or self.DEFAULT_DEEPSEEK_URL
        self.max_retries = max_retries
        self.backoff = backoff

        self.providers: List[str] = []
        if self.gemini_key:
            self.providers.append("gemini")
        if self.deepseek_key:
            self.providers.append("deepseek")
        if not self.providers:
            raise RuntimeError("Aucune clé LLM configurée. Définissez GEMINI_API_KEY ou DEEPSEEK_API_KEY.")

        self._provider_index = 0

    @property
    def _current_provider(self) -> str:
        return self.providers[self._provider_index]

    def _call_gemini(self, system_prompt: str, user_prompt: str) -> str:
        if not self.gemini_key:
            raise RuntimeError("Clé Gemini manquante")

        payload = {
            "systemInstruction": {"parts": [{"text": system_prompt}]},
            "contents": [{"role": "user", "parts": [{"text": user_prompt}]}],
            "generationConfig": {
                "temperature": 0.2,
                "maxOutputTokens": 2500,
            },
        }
        response = requests.post(
            f"{self.gemini_url}?key={self.gemini_key}",
            headers={"Content-Type": "application/json"},
            json=payload,
            timeout=60,
        )
        response.raise_for_status()

        data = response.json()
        candidates = data.get("candidates", [])
        if not candidates:
            raise RuntimeError("Réponse Gemini vide (aucun candidate)")

        parts = candidates[0].get("content", {}).get("parts", [{}])
        if not parts or "text" not in parts[0]:
            raise RuntimeError("Réponse Gemini mal formée")
        return parts[0]["text"]

    def _call_deepseek(self, system_prompt: str, user_prompt: str) -> str:
        if not self.deepseek_key:
            raise RuntimeError("Clé DeepSeek manquante")

        payload = {
            "model": "deepseek-chat",
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            "temperature": 0.2,
            "max_tokens": 2500,
        }
        response = requests.post(
            self.deepseek_url,
            json=payload,
            headers={
                "Authorization": f"Bearer {self.deepseek_key}",
                "Content-Type": "application/json",
            },
            timeout=60,
        )
        response.raise_for_status()

        choices = response.json().get("choices", [])
        if not choices:
            raise RuntimeError("Réponse DeepSeek vide")
        return choices[0]["message"]["content"]

    def chat(self, system_prompt: str, user_prompt: str) -> str:
        last_exception: Optional[Exception] = None

        for attempt in range(self.max_retries):
            try:
                if self._current_provider == "gemini":
                    return self._call_gemini(system_prompt, user_prompt)
                return self._call_deepseek(system_prompt, user_prompt)
            except (requests.RequestException, RuntimeError) as exc:
                last_exception = exc
                logger.warning(
                    "Tentative %s/%s échouée pour %s : %s",
                    attempt + 1,
                    self.max_retries,
                    self._current_provider,
                    exc,
                )

                # Bascule sur le fournisseur suivant s'il y en a plusieurs
                if len(self.providers) > 1:
                    self._provider_index = (self._provider_index + 1) % len(self.providers)

                if attempt < self.max_retries - 1:
                    time.sleep(self.backoff * (attempt + 1))

        raise last_exception or RuntimeError("Tous les fournisseurs LLM ont échoué")
