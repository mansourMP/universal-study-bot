# External Vocab Intake

Drop external vocab source files here before running merge audit.

Supported formats for `stage_vocab_merge_audit.py`:
- JSON (`vocabulary` array, `words` array, or top-level list)
- CSV (`hanzi,pinyin,meaning_en,source_level,source_name`)

Run:

```bash
python3 backend/scripts/stage_vocab_merge_audit.py \
  --db backend/learning_path.db \
  --source backend/content/sources/<file>.json \
  --source-name <dataset_name>
```
