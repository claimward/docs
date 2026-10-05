# Claimward documentation

[![Docs](https://github.com/claimward/docs/actions/workflows/docs.yml/badge.svg)](https://github.com/claimward/docs/actions/workflows/docs.yml) [![Site](https://img.shields.io/website?url=https%3A%2F%2Fclaimward.github.io%2Fdocs%2F&label=docs)](https://claimward.github.io/docs/)

Source of the Claimward documentation, published at
**<https://claimward.github.io/docs/>**.

A [Hugo](https://gohugo.io/) site with the [Hextra](https://github.com/imfing/hextra)
theme, laid out like the
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
the same page in the version chosen, or its home if the page is not there.
Search and the sidebar cover the version being read.

To publish a version:

```sh
git tag -a v0.2.0 -m "Documentation v0.2.0"
```

and push the tag. Choose the number by semver: **patch** for corrections,
**minor** for pages or sections added, **major** for a reorganisation that
breaks links. A tag in another form publishes nothing.

`v0.1.0` was built with MkDocs and mike before this site moved to Hugo. Its
directory on `gh-pages` is kept as it was published, and it reads the same
`versions.json`.

## Layout

| Path | What |
| --- | --- |
| `content/_index.md` | the home page |
| `content/<page>.md`, `content/<section>/` | the pages; `weight` orders the sidebar |
| `hugo.yaml` | `baseURL` of `dev`, the navbar (version › theme › search › GitHub), the brand mounts |
| `layouts/_partials/custom/version-select.html` | the version selector (reads `versions.json`) |
| `layouts/_partials/navbar.html` | Hextra's navbar, plus menu items drawn by a partial (the selector); keep in step with the theme |
| `layouts/_partials/favicons.html` | the brand's favicons |
| `layouts/_partials/custom/head-end.html` | Inter, from the brand |
| `layouts/_shortcodes/brand-lockup.html` | the logo on the home page, recoloured in the dark theme |
| `assets/css/custom.css` | the brand teal as Hextra's primary colour |
| `themes/hextra` | submodule: [imfing/hextra](https://github.com/imfing/hextra), pinned to a release tag |
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
reference fails the build. The "Last updated on" date at the foot of each page
comes from git.

## Working locally

```sh
git clone --recurse-submodules https://github.com/claimward/docs.git
cd docs
hugo server --baseURL http://localhost:1313/docs/dev/
```

then open <http://localhost:1313/docs/dev/>. Without a `versions.json` the
selector shows only the current version. Hugo 0.146 or later (CI uses the
version pinned in the workflow); no Python, no Node.

To upgrade the theme: `git -C themes/hextra checkout <tag>`, commit the
submodule, and compare `layouts/_partials/navbar.html` with the theme's.

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
