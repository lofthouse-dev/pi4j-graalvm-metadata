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

The plugin will:
1. Prompt for (or derive) the release version — e.g. `4.0.0-1`
2. Prompt for the tag name — defaults to `4.0.0-1` (matches the version)
3. Prompt for the next development version — e.g. `4.0.0-2-SNAPSHOT`
4. Run `mvn package` to verify the build (configured via `preparationGoals`)
5. Commit the release versions, create the tag, commit the next SNAPSHOT versions

Then push the branch and the tag:

```bash
git push && git push --tags
```

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

## Rolling back a failed release:prepare

If `release:prepare` fails or you need to undo it before pushing:

```bash
mvn release:rollback
```

This restores the POM versions and removes the local tag. If `rollback` is not available
(e.g. `release.properties` was deleted), do it manually:

```bash
git tag -d 4.0.0-1          # delete the local tag
git reset --hard HEAD~2      # undo the two release commits (check count with git log first)
```
