# Exercise scoring

The app assigns an integer score to a completed exercise based on active typing time and incorrect keystrokes:

\[
\text{score} = \operatorname{round}\left(100 \times \frac{T}{t} \times 0.95^{\,m-10}\right)
\]

- **T** is the baseline time in seconds: 120 for Könnyű, 180 for Közepes and Nehéz, 240 for Szupernehéz, and 180 for existing exercises.
- **t** is active typing time in whole seconds, with a minimum of 1 for this calculation. Only time during which the exercise accepts input is counted; fractional seconds are discarded before the minimum is applied.
- **m** is the number of incorrect keystrokes, including mistakes subsequently corrected.
- The result is rounded to the nearest integer.

At the baseline time and 10 mistakes, the score is **100**. With mistakes fixed, halving the time doubles the score before rounding. With time fixed, each additional mistake multiplies the score by 0.95, reducing it by 5% before rounding. The score has no fixed upper bound; very short attempts can produce large scores.

The examples below use a 180-second baseline.

| Active time | Mistakes | Score |
| --- | ---: | ---: |
| 180 seconds | 0 | 167 |
| 180 seconds | 10 | 100 |
| 180 seconds | 20 | 60 |
| 120 seconds | 10 | 150 |
| 240 seconds | 10 | 75 |

The score is announced after time and mistakes, followed by the numerical highest score for the same exercise. Records are stored locally; word drills keep separate records for Simple and Advanced modes. An attempt that changes mode during the exercise reports time and mistakes but receives no score and does not update records.

The first eligible attempt establishes the high score. Older records retain their best time and fewest mistakes, but cannot provide a historical high score: those two records may have come from different attempts.

The deleted sample exercise’s stored records are removed when records are loaded. Changing an exercise or its scoring settings does not automatically reset its high score; resetting affected records remains a manual responsibility.

This measures performance on an exercise. The separate [word difficulty model](word_difficulty.md) estimates the effort of typing a word and is not yet implemented.
