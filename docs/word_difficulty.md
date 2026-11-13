# Word typing difficulty

This document describes a proposed way to estimate the effort of typing a word on the Hungarian QWERTZ layout. It is not implemented in the app yet. The weights and thresholds are provisional and should be checked against learners' typing times and errors.

A word's difficulty is the sum of its character scores, including the transition adjustments below. Score each character using its physical key and the app's fixed finger assignments. Uppercase and lowercase letters have the same score; a Shift key is not counted. Spaces, punctuation, and other unsupported characters are outside the current rules.

## Base scores

| Base score | Keys | Rationale |
| --- | --- | --- |
| 1 | A S D F J K L É | Home-position keys |
| 2 | Q W E R U I O P G H Á Y X C V M | One straight reach from home |
| 3 | T Z Ő Í B N | One diagonal reach from home |
| 4 | Ö Ü Ó Ú Ű 0 1 2 3 4 5 6 7 8 9 | Double reach from home |

The straight paths follow the stagger of the keyboard rather than a strictly vertical line. These are simplified difficulty weights, not precise measurements of physical distance.

## Finger assignments

Use these assignments even if another touch-typing method uses a different finger. The home key is the reference point for transition adjustments; G, H, and Á are off-home keys, even though they are in the home row.

| Hand and finger | Home key | Assigned keys |
| --- | --- | --- |
| Left little | A | A Q Y Í 0 1 |
| Left ring | S | S W X 2 |
| Left middle | D | D E C 3 |
| Left index | F | F R T G V B 4 5 |
| Right index | J | J Z U H M N 6 7 |
| Right middle | K | K I 8 |
| Right ring | L | L O 9 |
| Right little | É | É P Á Ő Ú Ö Ü Ó Ű |

## Transition adjustments

Score the first character at its base value. For each later character, compare it with the immediately preceding character in the same word:

1. **Same key:** score the current character as 1, regardless of its base score. Do not apply a same-finger penalty.
2. **Different keys, same finger:** add 1 to the current character's base score if either key is that finger's home key; add 2 if both keys are off home.
3. **Different fingers:** use the current character's base score without adjustment.

The adjustment belongs to the second character. Start each word with no previous character.

## Examples

| Word | Character scores | Total |
| --- | --- | --- |
| AHA | 1 + 2 + 1 | 4 |
| ABBA | 1 + 3 + 1 + 1 | 6 |
| PÉNTEK | 2 + 2 + 3 + 3 + 2 + 1 | 13 |
| PÉNTEKI | 2 + 2 + 3 + 3 + 2 + 1 + 4 | 17 |
| PÁPUA | 2 + 4 + 4 + 2 + 1 | 13 |
| PÖPEC | 2 + 6 + 4 + 2 + 4 | 18 |

For example, P→É adds 1 to É because É is the right little finger's home key. P→Ö and Ö→P each add 2 because both keys are off home. The repeated B in ABBA scores 1 with no penalty.

## Difficulty bands

| Band | Word score |
| --- | --- |
| Easy | 10 or less |
| Medium | 11–20 |
| Hard | 21 or more |

For assembling 24-word lists, the proposed target totals are 192 for easy, 384 for medium, 576 for hard, and 768 for an **insane** list. Insane is a higher-target selection of hard words, not a separate word-level threshold. Each word must still meet its list's band, and totals may be approximate.

The score measures the effort of typing the entire word, so longer words tend to score higher. It is not a length-independent measure of difficulty.
