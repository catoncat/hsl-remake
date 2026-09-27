# OpenCC TSCharacters

`TSCharacters.txt` is the unmodified traditional→simplified single-character table of
[OpenCC](https://github.com/BYVoid/OpenCC) (Apache License 2.0), as shipped in
`opencc-python-reimplemented` 0.1.7 (`opencc/dictionary/TSCharacters.txt`).

The remake uses it only as a candidate list and as the set of traditional-only characters:
which form the original shows is read from the original font
(`docs/evidence_packets/static_reverse/original_font_script/`), and
`hsl check content:simplified_display` uses the keys as the set of traditional-only characters.
