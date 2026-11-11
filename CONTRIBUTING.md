# Contributing

Thanks for improving Stoker.

## Local checks

Before opening a pull request, run:

```sh
./scripts/validate.sh
```

It checks shell syntax, lints the generated launchd plists, runs the safe `dry-run` and
`app-status` paths, runs every test in `tests/`, and builds the app. CI runs the same script.

The script needs `jq`, `swiftc` and `file`, and fails without them. `shellcheck`, `plutil`
and `swift` are skipped when missing.

To add a test, create `tests/<name>.test.sh` and add a line for it in `scripts/validate.sh`.
Tests are not discovered automatically.

## Building the app

```sh
./app/StokerMenuBar/build-app.sh
open dist/Stoker.app
```

## Release packaging

```sh
./scripts/package-release.sh
```

This writes three files to `dist/`:

- `stoker-cli-<version>.tar.gz`: the command-line package.
- `stoker-gui-<version>.dmg`: the app, for most users.
- `stoker-gui-<version>.zip`: the app as a plain archive.

`STOKER_PLAIN_DMG=1` builds a plain DMG without the styled installer window. CI uses it. The
styled layout is given 60 seconds of Finder automation and falls back to a plain DMG.

Pushing a `v*` tag builds the same three files in CI and attaches them to a draft release.
Bump every version site first. `CLAUDE.md` lists them.

## Development notes

- Keep the default activation prompt tiny and explicit.
- Do not add dependencies unless they are needed for reliability.
- Do not commit generated logs, `.env`, `.omx`, `.omc`, `run/`, or generated plist files.
- Keep `run-now` clearly marked as a real usage-consuming action.
- Prefer portable Bash and macOS built-ins where possible.
- When you change `README.md`, `REFERENCE.md` or `INSTALL.md`, make the same change in the
  `_CN` file. Use the words the app itself shows for anything in its interface.

## Commit style

Use clear commit messages that explain why the change exists. If a change
affects scheduling, quota logging, or account state, include verification notes
in the commit body.

