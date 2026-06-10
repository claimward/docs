# Claimward documentation

Source for the Claimward documentation site, built with
[MkDocs Material](https://squidfunk.github.io/mkdocs-material/) and versioned with
[mike](https://github.com/jimporter/mike). Published at
<https://claimward.github.io/docs/>.

## Local preview

```sh
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
mkdocs serve            # http://127.0.0.1:8000
```

## Versioned builds (mike)

```sh
mike deploy 0.1 latest --update-aliases
mike set-default latest
mike serve              # preview the versioned site
```

CI (`.github/workflows/docs.yml`) deploys automatically:

- push to `main` → the `dev` version
- push a `vX.Y.Z` tag → that version, aliased `latest` and set as default

Both publish to the `gh-pages` branch. Enable **Settings → Pages → Deploy from
branch → `gh-pages`** once.

## License

BSD 3-Clause.
