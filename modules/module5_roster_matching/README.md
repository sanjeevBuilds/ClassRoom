# Module 5: Roster Matching, Evaluation & Paper Lead

**Owner**: Teammate 5

## Files (Phase 2+)
- `roster_db.py` — pre-enrolled student embedding store (SQLite/JSON), per the Roster
  Entry schema in `docs/interface_contract.md` §6.
- `cosine_matcher.py` — cosine similarity matching against the roster with asymmetric
  threshold logic (`τ_present` / `τ_match`), producing the Attendance Result schema
  (`docs/interface_contract.md` §7).
- `evaluator.py` (Phase 5) — ROC/PR curves, confusion matrices, accuracy-vs-speed plots.

**Hard deadline**: push a working, independently-tested version of this module by end of
Phase 2 (Sept 2) — see the roadmap's Phase 2 table for what "tested" means.
