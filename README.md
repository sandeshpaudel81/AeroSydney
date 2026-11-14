# Sydney Airports Flight Analytics

> A self-updating analytics pipeline and Power BI dashboard tracking flights at Sydney's two airports: Western Sydney International (WSI) and Sydney Airport (SYD).

<!-- TODO: add a dashboard screenshot here once Phase 5 is done -->

## Why this project

<!-- TODO: 2–3 sentences. WSI opened to passengers on 25 October 2026. What questions does this project answer? -->

## Business questions

1. How fast is WSI growing (flights, routes, airlines per week)?
2. What share of Sydney's flights does WSI carry?
3. Is WSI more or less punctual than SYD?
4. Is WSI using its no-curfew advantage (11pm–6am flights)?
5. How do the two route networks differ?

## Architecture

<!-- TODO: add docs/architecture.png and a one-line description of each step -->

| Layer | Tool |
| --- | --- |
| Source | <!-- TODO: which flight API? --> |
| Ingestion | Python |
| Storage | PostgreSQL (<!-- TODO: Neon / Supabase -->) |
| Transform | dbt Core |
| Orchestration | GitHub Actions |
| Visualisation | Power BI |

## Key findings

<!-- TODO (Phase 7): 3–5 findings, each one sentence with a number and a "so what" -->

## How to run it

<!-- TODO: setup steps — clone, create venv, install requirements, copy .env.example to .env, run the script -->

## Limitations and next steps

<!-- TODO: data history start date, API coverage, codeshare handling, what you'd add next -->

## Learning log

See [LEARNING_LOG.md](LEARNING_LOG.md).
