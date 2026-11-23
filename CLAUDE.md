# Instructions for AI assistants working in this repository

## Standing rule: keep RESEARCH_HANDOFF.md current (Kyle, 2026-11-22)

Every change that adds, removes or alters research, a model, a site feature, the weekly refresh, a data source or a
decision must update [RESEARCH_HANDOFF.md](RESEARCH_HANDOFF.md) in the same pull request:

1. Add a dated entry at the top of section 3 (Update log): what, result, status (LIVE / RESEARCH ONLY / REJECTED /
   PARKED / CLOSED) with PR numbers, files, assumptions touched, recommendations.
2. Update the area write-up in section 4 and the idea tables in section 5.
3. Add or change assumptions in section 6 (with the alternatives considered and why this one was chosen). Never delete
   an assumption; mark it SUPERSEDED with the date and add the new one.
4. Add known issues to section 8 and re-rank the future recommendations in section 9.
5. Change "Last updated" at the top.

Research that changes nothing live, and ideas that are rejected, still get an entry.

## Other rules

- This repository is public. Never commit API keys, Kyle's email, private mock drafts (StickToTheModel, Renner) or his
  personal league ids and trades.
- Build only what Kyle asked for; research requests are research only unless he says to publish.
- Never use KeepTradeCut data or NFL Mock Draft Database mocks other than Kyle's own (terms of use).
- Model parity: anything that feeds the mixed draft model must also feed the post-draft and pre-draft models where applicable.
- Trade-values page edits go in `Trade_Values/tv_page_template.html` and must also be copied to the PC's
  `Football2_Dynasty` folder before the Tuesday refresh.
