# Migrated to VWJF/rcg-sites

These workflow/action copies are **disabled** (GitHub Actions only loads `.github/workflows/*.yml` at the workflows root, not subfolders).

Active implementations live in [`VWJF/rcg-sites`](https://github.com/VWJF/rcg-sites) on branch `modularize` (until tagged releases).

Coastal `pages-gh.yml` is the dispatcher and calls `build.pages.yml` / `deploy.pages.yml` / `build.docker.yml` / `deploy.nomad.yml` there directly (one hop). Pass Nomad environment secrets by name. Do not call rcg-sites `pages-gh.yml` from coastal (sample only; nesting drops environment secrets).

Do not rely on these migrated copies remaining in sync; update `rcg-sites` instead.
