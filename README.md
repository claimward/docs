# Claimward documentation

[![Docs](https://github.com/claimward/docs/actions/workflows/docs.yml/badge.svg)](https://github.com/claimward/docs/actions/workflows/docs.yml) [![Site](https://img.shields.io/website?url=https%3A%2F%2Fclaimward.github.io%2Fdocs%2F&label=docs)](https://claimward.github.io/docs/)

Source of the Claimward documentation, published at
**<https://claimward.github.io/docs/>**.

A [Hugo](https://gohugo.io/) site with the [tannevaled/hextra](https://github.com/tannevaled/hextra)
fork of the [Hextra](https://github.com/imfing/hextra) theme, laid out like the
[GT-Cloud documentation](https://gt-cloud.resinfo.org/docs/development/), with
Claimward's branding.

## Versions

A version of the documentation is **a git tag** in strict
[semver](https://semver.org/) form, `vMAJOR.MINOR.PATCH`:

| Source | Published under |
| --- | --- |
| tag `v0.2.0` | `https://claimward.github.io/docs/v0.2.0/` |
| the newest tag | also `https://claimward.github.io/docs/latest/` |
| branch `main` | `https://claimward.github.io/docs/dev/` |

`https://claimward.github.io/docs/` redirects to `latest/`. The version
selector in the navbar lists every version from `docs/versions.json` and opens
the same page in the version chosen; if it is not there, the same page in
English (v0.1.0 to v0.2.1 are English only), else that version's home.
Search and the sidebar cover the version being read.

To publish a version:

```sh
git tag -a v0.2.0 -m "Documentation v0.2.0"
```

and push the tag. Choose the number by semver: **patch** for corrections,
**minor** for pages or sections added, **major** for a reorganisation that
breaks links. A tag in another form publishes nothing.

## Languages

English is the default and sits at the root of each version
(`/docs/<version>/getting-started/`); French, Spanish and German are under
`/fr/`, `/es/` and `/de/` (`/docs/<version>/fr/getting-started/`). The language switch at the foot of
the sidebar opens the same page in the other language, in the same version.

To add a language `<lang>`:

1. `content/<lang>/`: a translation of every page, with the same file names
   (that is how a page and its translation are paired). A translated heading
   keeps the English one's anchor as an explicit id
   (`## Locataires {#tenants}`), so the relrefs resolve in every language.
2. `i18n/<lang>.yaml`: the site's own strings (copyright, version).
3. A `languages.<lang>` entry in `hugo.yaml`: label, `contentDir`, weight,
   `params.flag`, and the translated `params.description`.
4. Its flag in `static/images/flags/`, from
   [lipis/flag-icons](https://github.com/lipis/flag-icons) (4x3, MIT).

Declare a language only with its content: a declared language without pages
is an empty entry in the switch.

`v0.1.0` was built with MkDocs and mike before this site moved to Hugo. Its
directory on `gh-pages` is kept as it was published, and it reads the same
`versions.json`.

## Layout

| Path | What |
| --- | --- |
| `content/en/`, `content/fr/` | the pages, one directory per language with the same file names; `_index.md` is the home, `weight` orders the sidebar |
| `i18n/<lang>.yaml` | the site's strings, beside the theme's |
| `static/images/flags/` | the language switch's flags (lipis/flag-icons, MIT) |
| `hugo.yaml` | `baseURL` of `dev`, the languages, the navbar (version › theme › search › GitHub), the brand mounts |
| `layouts/_partials/custom/version-select.html` | the version selector (reads `versions.json`) |
| `layouts/_partials/favicons.html` | the brand's favicons |
| `layouts/_partials/custom/head-end.html` | Inter, from the brand |
| `layouts/_shortcodes/brand-lockup.html` | the logo on the home page, recoloured in the dark theme |
| `assets/css/custom.css` | the brand teal as Hextra's primary colour |
| `themes/hextra` | submodule: [tannevaled/hextra](https://github.com/tannevaled/hextra), pinned to a release tag (upstream Hextra plus opt-in features: partial menu items, related sites, page subtitle and history) |
| `branding` | submodule: [claimward/brand](https://github.com/claimward/brand) (logos, favicons, Inter) |
| `scripts/publish-version.sh` | puts one build into a `gh-pages` checkout and rewrites `versions.json`, `latest` and the root redirect |

## Writing a page

Each page starts with a title, a one-sentence description, and tags:

```yaml
---
title: "Tenants"
weight: 40
description: "Routes are scoped to tenants. A person may belong to several, and chooses one per session."
tags: [tenants, server, grpc]
---
```

Link to other pages with `{{< relref "/components/server.md" >}}`: a broken
reference fails the build. The page history at the foot of each page (created, modified,
by whom) comes from git: `themes/hextra/scripts/page-history.sh` writes
`data/pagehistory.json` before the build.

## Working locally

```sh
git clone --recurse-submodules https://github.com/claimward/docs.git
cd docs
mkdir -p data && sh themes/hextra/scripts/page-history.sh > data/pagehistory.json
hugo server --baseURL http://localhost:1313/docs/dev/
```

then open <http://localhost:1313/docs/dev/>. Without a `versions.json` the
selector shows only the current version. Hugo 0.146 or later (CI uses the
version pinned in the workflow); no Python, no Node.

To upgrade the theme: `git -C themes/hextra checkout <tag>` (a tag of the
fork), commit the submodule, and run the production build of the workflow:
the fork's features are opt-in and its own CI does not build them, so this
site's `--panicOnWarning` build is their test.

## Publication

`.github/workflows/docs.yml`:

| Job | When | What |
| --- | --- | --- |
| `build` | pull requests, `main`, tags `v*` | builds with `--baseURL …/docs/<version>/`, checks internal links and anchors, uploads the site |
| `deploy` | `main`, tags `vX.Y.Z` | `scripts/publish-version.sh` into `gh-pages`, then a commit and a push; one deploy at a time |

GitHub Pages serves the `gh-pages` branch (**Settings → Pages → Deploy from a
branch**).

## License

BSD 3-Clause.
