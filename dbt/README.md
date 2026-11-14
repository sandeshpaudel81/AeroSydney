# dbt (Phase 4)

Empty on purpose. In Phase 4, from this folder run:

```
pip install dbt-postgres
dbt init sydney_airports
```

Then create `models/staging/` (clean + rename raw data) and `models/marts/` (the star schema), and add tests in `schema.yml` files.
