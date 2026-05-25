# TODO

- Regenerate results and plots after the recent code changes.
  Existing ignored `results/` and `plots/` files may still reflect older transmission headers/units.

- Finish `ANSWERS.md`.
  This is user-written and should be completed manually.

- Keep `AI_ANSWERS.md`.
  Use it as a comparison/reference draft while writing `ANSWERS.md`.

- Add optional cross-exercise comparison plots:
  - Total system cost by exercise.
  - CO2 emissions by exercise.
  - Battery capacity by country across Exercises 2b, 3, and 4.
  - Transmission comparison between Exercises 3 and 4.
  - Nuclear impact from Exercise 3 to 4.

- Discuss/report Exercise 2a infeasibility.
  The answer text should clearly explain that Exercise 2a is infeasible under the current
  formulation/data.

- Decide how to discuss the very large Exercise 2b battery capacity.
  This likely deserves a note as a model-simplification artifact, because batteries are modeled as
  1 MW = 1 MWh.

- Decide whether a more formal mathematical formulation is needed.
  Add one if the supervisor expects full notation rather than a written model description.

- Clean minor code TODOs if desired:
  - `data.jl`: replace repeated technology parameter dictionaries with a single structure.
  - `data.jl`: decide whether to remove explicit hydro entries for non-Sweden.
  - Maybe remove hydro from the free `capacity` decision variable, since hydro capacity is fixed
    by assignment data. This would be conceptually cleaner, but requires separate technology sets
    for generation and investable capacity, plus special handling in constraints and result output.

- Consider runtime/model improvements.
  Exercises 3 and 4 are slow. Deeper changes such as solver options, scaling, or time aggregation
  need an explicit decision because they may affect results or the formulation.
