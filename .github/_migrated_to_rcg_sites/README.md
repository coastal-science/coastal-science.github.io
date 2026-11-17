# Migrated composite actions

`cleanup-pr-nomad-job` and the reusable `cleanup.nomad.delete.yml` live in [`VWJF/rcg-sites`](https://github.com/VWJF/rcg-sites). Coastal keeps a thin `on: delete` entrypoint that calls:

`uses: VWJF/rcg-sites/.github/workflows/cleanup.nomad.delete.yml@modularize`

This directory is a disabled local copy only. (The historical coastal action pin `@83c69391…` remains valid for that commit SHA.)
