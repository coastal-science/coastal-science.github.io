# Migrated to VWJF/rcg-sites

These workflow/action copies are **disabled** (GitHub Actions only loads `.github/workflows/*.yml` at the workflows root, not subfolders).

Active implementations live in [`VWJF/rcg-sites`](https://github.com/VWJF/rcg-sites) on branch `modularize` (until tagged releases).

Coastal `site.dispatch.yml` is the dispatcher and calls `build.pages.yml` / `deploy.pages.yml` / `build.docker.yml` / `deploy.nomad.yml` there directly (one hop), plus gated `cleanup-runner` for self-hosted/rcg. Pass Nomad environment secrets by name. Do not call rcg-sites `site.dispatch.yml` from coastal (sample only; nesting drops environment secrets).

`pages-custom.yml` is obsolete here: it only defaulted `runs_on` and owned cleanup; both live in `site.dispatch` / `manual.dispatch` now (same as rcg-sites).

Do not rely on these migrated copies remaining in sync; update `rcg-sites` instead.
