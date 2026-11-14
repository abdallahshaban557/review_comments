# review_comments

Shared runtime, local `127.0.0.1` sync server, multi-framework source-line
locator, and coding-agent CLI backing
[`review_comments_jaspr`](../review_comments_jaspr) and
[`review_comments_flutter`](../review_comments_flutter).

> **Tip:** If you are building a **Jaspr** or **Flutter Web** app, you only need
> to depend on `review_comments_jaspr` or `review_comments_flutter`—both include
> this package and re-export the `review_comments` CLI executable automatically.

## Entrypoints

- `package:review_comments/review_comments.dart` — Web, Wasm, and VM-safe config,
  models, XSS-safe JSON script encoding, and Shadow DOM overlay runtime.
- `package:review_comments/cli.dart` — `ReviewLocalServer`,
  `locateHighlightInRepo`, `ReviewProjectConfig`, and `ReviewCommand`.

## CLI Commands

```bash
dart run review_comments serve -- <your dev server command>
dart run review_comments list
dart run review_comments prompt
dart run review_comments resolve <id | --all>
dart run review_comments clear [--resolved | --all]
```
