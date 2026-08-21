## What

<!-- One or two sentences: what does this PR change and why? -->

## How tested

- [ ] `flutter analyze --fatal-infos` passes
- [ ] `flutter test` passes locally
- [ ] CI checks are green

## Risk & rollback

- [ ] Bug fix — no behavior change, safe to ship
- [ ] Behavior change — described in `changelog` and the App Store / APK
      release notes
- [ ] Rollback plan: revert the commit (the release pipeline does not
      sign or auto-push new releases; revert = done)

## Reviewer checklist

<!-- For the human approving this PR. -->
- [ ] I am **not** the author of this PR
- [ ] Code I own that this PR touches is fully reviewed (see `.github/CODEOWNERS`)
- [ ] No secrets, tokens or keys in the diff
- [ ] No change to `pubspec.yaml` version unless release-relevant
- [ ] Test plan matches the actual change
