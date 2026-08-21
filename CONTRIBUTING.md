# Contributing

## Workflow

1. Branch off `main`. Short-lived feature branches with one PR each.
2. Open the PR early, even as a draft — CI starts immediately and gives
   you faster feedback than local runs.
3. CI checks (`analyze-and-test` + `build-linux`) must be green before
   review.
4. The PR needs **1 approval**, and it cannot be the author. The
   approver is automatically requested from the owners listed in
   `.github/CODEOWNERS` for the directories this PR touches.
5. `main` is protected: force-push, deletion, and direct pushes are
   blocked. Squash-merge only — history is linear.
6. The release bot opens its own PR for the PKGBUILD/pubspec version
   sync after each tag; it merges itself via auto-merge when CI is
   green, no human action needed.

## Releases

- Cut from `main` with `./scripts/release.sh`. The script picks the
  next patch (or minor/major) version, refuses to run if the working
  tree is dirty, and pushes the tag.
- The pipeline that fires on tag push runs build and tests on
  `ubuntu-latest`, signs artifacts, uploads them to the GitHub
  Release, and only `deploy-updates` waits for the `release`
  environment approval. **One click per release, not three.**
- If `deploy-updates` fails after artifacts are already on the
  GitHub Release, you can rerun just that step from the Actions tab:
  `Release & Deploy → Run workflow → enter the existing tag`. No new
  tag required.
- Code owners listed the first time they are touched automatically
  become required reviewers via the `protect-main` ruleset.

## Code owners

`.github/CODEOWNERS` maps directories to GitHub handles. It is the
ground truth for "who must look at this file". Update it when
responsibilities shift, in the same PR as the first change that uses
the new owner.

## Security

See `SECURITY.md`. Do not file vulnerability reports as public issues.
