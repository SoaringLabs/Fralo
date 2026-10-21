# Plane DevFlow migration for Fralo

This bundle is copied from Plane DevFlow **0.10.1** (`3cf150da1c842f50533d57f09a3493d8335bd40c`). The repository mapping is renamed to [`.plane-devflow.json`](../../.plane-devflow.json) with its contents unchanged. The existing Plane project, repository/base branch, completion preferences, MCP connection and `PLANE_API_KEY` Secret are retained.

Schema 2, empty state targets and disabled state synchronization remain unchanged. PR activity can be recorded without changing the Plane task state.

## What changes

- `.github/plane-for-codex/` → `.github/plane-devflow/`; both runtime scripts match the released bundle.
- `.github/workflows/plane-for-codex.yml` → `.github/workflows/plane-devflow.yml`, including the sparse checkout, runner path and concurrency group.
- New PR comments use the `plane-devflow` namespace. Historical PRs/comments are preserved. Existing bracketed task titles remain recognized; new binding blocks use `plane-devflow`.
- Local response snapshots and Python bytecode are excluded from commits. This PR contains no task receipts, credentials, application changes or task state requests.

## Validate before merge

```sh
python3 .github/plane-devflow/test_sync.py -v
```

The [candidate validation workflow](../workflows/plane-devflow-validation.yml) runs this test against PR code with read-only repository access and without Plane credentials. HTTP is mocked or blocked. It checks manual acceptance, terminal states, event retries, latest-PR reconciliation, cross-project/repository rejection and trusted-base configuration reads.

The production `pull_request_target` workflow executes only scripts/configuration from the trusted base SHA, never the PR head. A migration PR without a business-task binding is skipped by the existing synchronization workflow.

## Activate after an authorized merge

1. Merge this PR only after explicit approval. Until then, the default branch continues using its original workflow/configuration; the new production workflow is not active.
2. Run the new read-only connection check on the default branch:

   ```sh
   gh workflow run plane-devflow.yml --ref main
   ```

3. Verify a later authorized task PR event separately. A connection check or an unbound migration PR does not prove real task writeback.
4. Before resuming an older task checkout, review and synchronize its recorded branch with the migrated base using its normal task workflow. Keep existing branches, receipts, execution paths and human acceptance/merge decisions; do not recreate setup or bulk-rewrite historical PRs.

Existing task/worktree metadata stays local and is not moved, deleted or reset by this PR. A task checkout still based on the previous configuration is not automatically updated when this PR merges. Rollback of tracked files must also be reviewed; restoring filenames does not undo already emitted external events.
