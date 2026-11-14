## 0.2.0

- Simplify PR Preview comment composer actions: replace the redundant secondary
  `Copy gh CLI Command` button with an `Add GitHub Token…` shortcut alongside
  `Pin & Copy gh CLI` when no token is saved, and show a clean single
  `Post to PR #<N>` button when a token is configured (preserving typed draft
  text across Settings updates).

## 0.1.0

- Initial release combining the Shadow DOM visual review overlay, GitHub PR
  inline diff line mapper, shell-safe `gh` CLI builder, loopback
  `ReviewLocalServer`, multi-framework `ReviewSourceLocator`, and
  `review_comments` CLI.
