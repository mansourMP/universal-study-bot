#!/usr/bin/env python3
"""Filtering helpers for HSK1 image generation queues."""

from __future__ import annotations

import re


CONCRETE_OBJECT_CONCEPTS = {
    "admission_ticket",
    "airplane",
    "ball",
    "bed",
    "book",
    "bread",
    "building",
    "car",
    "clothes",
    "computer",
    "cooked_rice",
    "cup",
    "desk",
    "dish_or_vegetable",
    "door",
    "doorway",
    "egg",
    "flower",
    "fruit",
    "glass",
    "hair_or_fur",
    "hand",
    "library",
    "map",
    "meat",
    "milk",
    "mobile_phone",
    "money",
    "moon",
    "mountain",
    "noodles",
    "notebook",
    "plane_ticket",
    "tea",
    "telephone",
    "ticket",
    "train",
    "train_ticket",
    "vegetable",
    "water",
}

CONCRETE_OBJECT_TOKENS = {
    "airplane",
    "apple",
    "ball",
    "bed",
    "book",
    "bread",
    "building",
    "bus",
    "car",
    "chair",
    "clothes",
    "computer",
    "cup",
    "desk",
    "door",
    "egg",
    "flower",
    "fruit",
    "glass",
    "hair",
    "hand",
    "library",
    "map",
    "meat",
    "milk",
    "mobile",
    "phone",
    "money",
    "moon",
    "mountain",
    "noodles",
    "notebook",
    "rice",
    "tea",
    "telephone",
    "ticket",
    "train",
    "vegetable",
    "water",
    "bicycle",
    "bike",
}

ABSTRACT_TOKENS = {
    "you",
    "your",
    "i",
    "me",
    "he",
    "she",
    "they",
    "we",
    "my",
    "our",
    "their",
    "please",
    "sorry",
    "welcome",
    "ask",
    "may",
    "can",
    "could",
    "would",
    "should",
    "not",
    "is",
    "are",
    "am",
    "was",
    "were",
    "be",
    "do",
    "does",
    "did",
    "to",
    "in",
    "on",
    "at",
    "from",
    "with",
    "for",
    "of",
    "and",
    "or",
    "if",
    "how",
    "what",
    "when",
    "where",
    "why",
    "this",
    "that",
    "these",
    "those",
    "here",
    "there",
    "today",
    "tomorrow",
    "yesterday",
    "morning",
    "afternoon",
    "evening",
    "year",
    "month",
    "day",
    "hour",
    "minute",
    "second",
    "time",
    "again",
    "first",
    "last",
    "next",
    "same",
    "few",
    "little",
    "many",
    "much",
    "big",
    "small",
    "good",
    "bad",
    "best",
    "correct",
    "common",
    "important",
    "difficult",
    "easy",
    "fast",
    "slow",
    "hot",
    "cold",
    "expensive",
    "cheap",
}

EXCLUDED_TOKENS = {
    "get",
    "go",
    "come",
    "playing",
    "play",
    "teaching",
    "busy",
    "see",
    "having",
    "hold",
    "online",
    "friend",
    "person",
    "people",
    "teacher",
    "student",
    "doctor",
    "mother",
    "dad",
    "child",
    "boy",
    "girl",
    "man",
    "woman",
    "family",
}


def _tokenize(s: str) -> set[str]:
    return {t for t in re.split(r"[^a-z0-9]+", s.lower()) if t}


def is_memorization_object_row(
    *,
    category: str,
    name_en: str,
    concept_key: str,
    recommended_filename: str,
) -> bool:
    """Return True only for concrete visual object targets."""
    if (category or "").strip() != "object_scene":
        return False

    fn = (recommended_filename or "").strip().lower()
    ck = (concept_key or "").strip().lower()
    if ck.startswith("object_"):
        ck = ck[7:]

    tokens = _tokenize(f"{name_en} {ck} {fn}")
    if tokens & EXCLUDED_TOKENS:
        return False

    if fn.startswith(("object_food_", "object_vehicle_", "object_electronics_")):
        return True

    if ck in CONCRETE_OBJECT_CONCEPTS:
        return True

    if (tokens & CONCRETE_OBJECT_TOKENS) and not (tokens & ABSTRACT_TOKENS):
        return True

    return False

