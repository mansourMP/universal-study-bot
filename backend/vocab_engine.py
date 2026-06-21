import json
import re
from typing import List, Dict, Set, Tuple, Optional

class Token:
    def __init__(self, text: str, token_type: str, start: int, end: int, vocab_id: Optional[str] = None):
        self.text = text
        self.type = token_type  # VOCAB, NAME, PUNCT, UNK
        self.start = start
        self.end = end
        self.vocab_id = vocab_id

    def to_dict(self):
        return {
            "text": self.text,
            "type": self.type,
            "start": self.start,
            "end": self.end,
            "vocab_id": self.vocab_id
        }

class HSK1Tokenizer:
    def __init__(self, vocab_path: str):
        self.vocab_set: Set[str] = set()
        self.vocab_map: Dict[str, dict] = {} # Map hanzi to full vocab object
        self.max_token_len = 0
        self.load_vocab(vocab_path)
        
        # Regex for basic punctuation and latin names
        self.punct_pattern = re.compile(r"[^\w\s\u4e00-\u9fff]|[，。！？、；：“”‘’（）【】《》…—]")
        self.latin_name_pattern = re.compile(r"[A-Za-z]+(?:\s+[A-Za-z]+)*")

    def load_vocab(self, path: str):
        try:
            with open(path, 'r', encoding='utf-8') as f:
                data = json.load(f)
                vocab_list = data.get('vocabulary', [])
                for item in vocab_list:
                    hanzi = item.get('hanzi')
                    if hanzi:
                        self.vocab_set.add(hanzi)
                        self.vocab_map[hanzi] = item
                        self.max_token_len = max(self.max_token_len, len(hanzi))
            print(f"Loaded {len(self.vocab_set)} HSK1 vocabulary items. Max length: {self.max_token_len}")
        except Exception as e:
            print(f"Error loading vocab: {e}")

    def tokenize_line(self, text: str) -> List[Token]:
        tokens = []
        i = 0
        n = len(text)
        
        while i < n:
            # 1. Skip whitespace
            if text[i].isspace():
                i += 1
                continue
                
            # 2. Try Longest-Match Vocab
            matched = False
            # Clamp max length to remaining string length
            current_max_len = min(self.max_token_len, n - i)
            
            for length in range(current_max_len, 0, -1):
                candidate = text[i : i + length]
                if candidate in self.vocab_set:
                    tokens.append(Token(candidate, "VOCAB", i, i + length, self.vocab_map[candidate].get('hanzi'))) # using hanzi as ID for now
                    i += length
                    matched = True
                    break
            
            if matched:
                continue

            # 3. Check for Latin Names (e.g., Mansur, Miriam)
            # We look ahead for a latin sequence
            latin_match = self.latin_name_pattern.match(text, pos=i)
            if latin_match and latin_match.start() == i:
                span = latin_match.group()
                tokens.append(Token(span, "NAME", i, i + len(span)))
                i += len(span)
                continue

            # 4. Check Punctuation
            # A simple check: is it non-alphanumeric and not CJK unified ideograph?
            # Or use explicit list.
            char = text[i]
            # Simple heuristic for punctuation/symbol
            if self.punct_pattern.match(char) or not char.strip():
                 tokens.append(Token(char, "PUNCT", i, i + 1))
                 i += 1
                 continue

            # 5. Fallback: UNK (Unknown Hanzi or character)
            tokens.append(Token(char, "UNK", i, i + 1))
            i += 1
            
        return tokens

class ContentLinter:
    def __init__(self, tokenizer: HSK1Tokenizer):
        self.tokenizer = tokenizer

    def lint_text(self, text: str, context_name: str = "Unknown"):
        tokens = self.tokenizer.tokenize_line(text)
        
        unknowns = [t for t in tokens if t.type == "UNK"]
        names = [t for t in tokens if t.type == "NAME"]
        vocabs = [t for t in tokens if t.type == "VOCAB"]
        
        unique_vocab = set(t.text for t in vocabs)
        
        report = {
            "context": context_name,
            "total_tokens": len(tokens),
            "unknown_count": len(unknowns),
            "unknown_tokens": [t.text for t in unknowns],
            "names": [t.text for t in names],
            "vocab_coverage": len(vocabs) / len(tokens) if tokens else 0.0,
            "unique_vocab": list(unique_vocab),
            "status": "PASS" if not unknowns else "FAIL"
        }
        
        return report, tokens

if __name__ == "__main__":
    # Self-test if run directly
    import sys
    
    # Path to your actual vocab file
    VOCAB_PATH = "backend/content/packs/zh_hsk1_vocab.json"
    
    tokenizer = HSK1Tokenizer(VOCAB_PATH)
    linter = ContentLinter(tokenizer)
    
    test_sentences = [
        "你好！我是Amara。", # Should have Name
        "我去北京。",      # All HSK1
        "我喜欢编程。"      # "编程" (Programming) is likely UNK
    ]
    
    print("-" * 30)
    print("RUNNING SELF-TEST")
    print("-" * 30)
    
    for sent in test_sentences:
        report, _ = linter.lint_text(sent, sent)
        print(f"Sentence: {sent}")
        print(f"Status: {report['status']}")
        if report['unknown_tokens']:
            print(f"Unknowns: {report['unknown_tokens']}")
        print(f"Names: {report['names']}")
        print("-" * 10)
