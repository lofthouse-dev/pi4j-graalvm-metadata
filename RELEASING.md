# Releasing

## Version scheme

Versions follow `<pi4j-version>-<metadata-patch>`, e.g. `4.0.0-1`.

- `main` always carries a `-SNAPSHOT` suffix: `4.0.0-1-SNAPSHOT`
- Release tags match the bare version with no prefix: `4.0.0-1`
- The GraalVM version is encoded in the `artifactId` (`graal25`), not the Maven version

Bump the metadata patch number when:
- A GraalVM patch upgrade changes the set of captured downcall descriptors
- Any other change to the captured metadata is needed

When the Pi4J version changes, update the pi4j-version component and reset the metadata
patch to 0 — e.g. `4.0.0-3-SNAPSHOT` → `5.0.0-0-SNAPSHOT`.

## Release procedure

From a **clean working tree** on `main`:

```bash
mvn --batch-mode release:prepare
```

With `--batch-mode` the plugin runs fully non-interactively. It derives versions
automatically from the current SNAPSHOT:

1. Strips `-SNAPSHOT` to produce the release version — e.g. `4.0.0-1-SNAPSHOT` → `4.0.0-1`
2. Tags using that version — e.g. `4.0.0-1`
3. Increments the metadata patch for the next dev version — e.g. `4.0.0-2-SNAPSHOT`
4. Runs `mvn package` to verify the build (configured via `preparationGoals`)
5. Commits and **pushes** the release version, the tag, and the next SNAPSHOT version

No separate `git push` is needed — the plugin pushes everything automatically.

GitHub Actions picks up the tag and publishes the artifact automatically (see CI below).

**Do not run `mvn release:perform`.** Publishing is handled by CI on tag push.

## What CI does

The `.github/workflows/publish.yml` workflow triggers on any tag matching `[0-9]*`.
It runs `mvn deploy`, which:
- Builds the probe JAR
- Runs the native-image-agent inside the `graalvm-pi-builder` container to capture metadata
- Deploys `pi4j-ffm-metadata-bookworm-graal25` to GitHub Packages

Permissions are provided automatically via `GITHUB_TOKEN`.

## Verifying a release

After the workflow completes, the package should appear at:

```
https://github.com/lofthouse-dev/pi4j-graalvm-metadata/packages
```

Consumers can resolve the artifact as described in the [Readme.md](Readme.md).

## Rolling back a release:prepare

Because the plugin pushes automatically, rollback depends on how far it got.

**If it failed before pushing** — run:

```bash
mvn release:rollback
```

This restores the POM versions and removes the local tag. If `rollback` is not available
(e.g. `release.properties` was deleted), do it manually:

```bash
git tag -d 4.0.0-1          # delete the local tag
git reset --hard HEAD~2      # undo the two release commits (check count with git log first)
```

**If it pushed successfully** — you need to revert on the remote too:

```bash
git push origin :4.0.0-1                    # delete the remote tag
git push --force-with-lease origin main      # push the reset branch (after local reset above)
```
