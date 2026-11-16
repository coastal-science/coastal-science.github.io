# Migrated to VWJF/rcg-sites

These workflow/action copies are **disabled** (GitHub Actions only loads `.github/workflows/*.yml` at the workflows root, not subfolders).

Active implementations live in [`VWJF/rcg-sites`](https://github.com/VWJF/rcg-sites) on branch `refactor-from-cs` (until tagged releases).

Coastal `pages-gh.yml` is the dispatcher and calls `deploy-github-pages.yml` / `deploy-nomad.yml` there directly (one hop so environment secrets inherit). Do not call rcg-sites `pages-gh.yml` from coastal (nested A→B→C drops environment secrets).

Do not rely on these migrated copies remaining in sync; update `rcg-sites` instead.
