# pi4j-graalvm-metadata

GraalVM reachability metadata for `com.pi4j:pi4j-plugin-ffm:4.0.2`.

## What it does

This repository produces a zero-code Maven JAR that contains a pre-captured
`reachability-metadata.json` for Pi4J's Foreign Function & Memory (FFM) plugin. Without it,
any Pi4J-based GraalVM native image fails at runtime with a `MissingForeignRegistrationError`:

```
com.oracle.svm.core.jdk.proxy.MissingForeignRegistrationError: ...
```

The root cause is that the FFM plugin calls `Linker.nativeLinker().downcallHandle()` at class
initialisation time with a specific set of `FunctionDescriptor` shapes (one per Linux syscall or
library function). GraalVM's `native-image` must know all these shapes at build time. The metadata
JAR registers all 21 unique downcall descriptors that Pi4J requires.

Adding the JAR as a Maven dependency is all a consumer needs to do — `native-image` discovers
the metadata automatically from the classpath.

## Why

Pi4J's FFM plugin uses the Java Foreign Function & Memory API (finalized in Java 22) to call
Linux system calls and library functions directly from Java, without JNI. This makes the code
cleaner and faster, but it introduces a GraalVM native-image challenge: every unique
`FunctionDescriptor` passed to `downcallHandle()` must be registered in the native image at build
time, or the application will fail at runtime.

Rather than requiring every Pi4J application to configure the `native-image-agent` themselves,
this library ships the pre-captured metadata so it is applied automatically.

## Published artifact

| Artifact | Coordinates |
|---|---|
| **Metadata JAR** | `dev.lofthouse.pi4j:pi4j-ffm-metadata-bookworm-graal25:4.0.2-0` |

The artifactId encodes the capture environment: `bookworm` = Debian 12 (same glibc as
Raspberry Pi OS 12), `graal25` = GraalVM CE major version 25.

**Versioning scheme:** `<pi4j-version>-<metadata-patch>` — e.g. `4.0.2-0`. The GraalVM patch
version is not in the Maven version; it is encoded in the artifactId.

## Using the artifact

Add the following to your project's `pom.xml`:

```xml
<repositories>
  <repository>
    <id>github-pi4j-graalvm-metadata</id>
    <url>https://maven.pkg.github.com/lofthouse-dev/pi4j-graalvm-metadata</url>
  </repository>
</repositories>

<dependencies>
  <dependency>
    <groupId>dev.lofthouse.pi4j</groupId>
    <artifactId>pi4j-ffm-metadata-bookworm-graal25</artifactId>
    <version>4.0.2-0</version>
  </dependency>
</dependencies>
```

GitHub Packages requires a GitHub personal access token (PAT) with the `read:packages` scope.
Add the following to your Maven `~/.m2/settings.xml`:

```xml
<settings>
  <servers>
    <server>
      <id>github-pi4j-graalvm-metadata</id>
      <username>YOUR_GITHUB_USERNAME</username>
      <password>YOUR_GITHUB_PAT</password>
    </server>
  </servers>
</settings>
```

## Prerequisites (building from source)

| Requirement | Details |
|---|---|
| **Java** | GraalVM CE 25 (or any JDK 25+; GraalVM is needed inside the container) |
| **Maven** | 3.9+ |
| **Podman** | Must be on `PATH`; used to run the `graalvm-pi-builder` container |
| **Container image** | The version-pinned `graalvm-pi-builder` tag in [`graalvm-pi-builder.env`](graalvm-pi-builder.env) (currently `bookworm-25.5.5.0.3`) — pulled automatically on first run; the same image is used locally and in CI |

> **Note:** Docker is not supported. The build scripts use `podman` explicitly.

The container image is `debian:bookworm` + GraalVM CE 25 + `libi2c-dev`. It is built in the
`graalvm-pi-builder/` directory of the `iron-j` repository.

## Building

```bash
mvn package
```

This runs the full build:
1. Compiles and packages the probe fat JAR (`probe/target/probe.jar`).
2. Runs `scripts/generate-metadata.sh` inside the container with `native-image-agent`.
3. The captured `reachability-metadata.json` lands in
   `metadata/target/generated-resources/META-INF/native-image/com.pi4j/pi4j-plugin-ffm/`
   and is packaged directly into the metadata JAR.

Nothing is committed; the generated file is gitignored.

### Regenerating metadata standalone

To regenerate the metadata JSON outside the Maven build (e.g. after updating Pi4J):

```bash
bash scripts/run-probe.sh
```

Output: `generated-config/reachability-metadata.json` (gitignored).

### Overriding the container image

By default the build uses the image pinned in [`graalvm-pi-builder.env`](graalvm-pi-builder.env).
Set `GRAALVM_PI_BUILDER_IMAGE` to use a different one, such as a locally built image:

```bash
GRAALVM_PI_BUILDER_IMAGE=ghcr.io/lofthouse-dev/graalvm-pi-builder:latest mvn package
```

### Releasing

See [RELEASING.md](RELEASING.md) for the full release procedure.

## CI

Pull requests targeting `main` are built automatically via `.github/workflows/build.yml`.
The workflow can also be triggered manually via `workflow_dispatch`.

The CI build:
1. Installs Temurin 25 on the runner to compile the probe JAR.
2. Sets up QEMU binfmt for arm64 emulation (needed to run the arm64 container on x86_64).
3. Runs `mvn package` with `GRAALVM_PI_BUILDER_IMAGE` taken from
   [`graalvm-pi-builder.env`](graalvm-pi-builder.env), a version-specific container tag
   (currently `bookworm-25.5.5.0.3`) rather than the mutable `bookworm-graal25` tag, for
   reproducibility. `publish.yml` reads the same file, so a release is built from the image CI
   tested.
4. Caches both Maven dependencies and the container image between runs.

### Metadata drift workflow

`.github/workflows/metadata-drift.yml` answers "does the captured metadata still match the latest
release?" without a manual comparison, and reports newer inputs. It never releases anything
(releases are manual, see [RELEASING.md](RELEASING.md)).

It runs on a weekly schedule (Mondays 06:17 UTC), on `workflow_dispatch`, and on pull requests
that touch the builder pin, `pom.xml`, `metadata/pom.xml`, the probe, the scripts below or the
workflow itself. It has three jobs, so that code from a pull request never runs with issue-write
access: `drift` (generate and compare; read-only token, git credentials not persisted), `report`
(updates the tracking issue; the only job with `issues: write`, and it runs only on scheduled runs
and manual runs that ask for it) and `verdict` (fails the run when the metadata differs or a job
failed). The `drift` job:

1. Generates the metadata on the pinned image, exactly like the CI build.
2. Fetches `reachability-metadata.json` from the jar of the latest release. The latest release is
   the highest version tag (history is linear); the jar comes from GitHub Packages using the
   workflow's `GITHUB_TOKEN` (`packages: read`). The artifactId is read from the `metadata/pom.xml`
   at that tag, so the comparison still works on the commit that moves to a new GraalVM major
   (`graal25` to `graal26`), when the latest release only contains the old artifact.
3. Compares the two with `scripts/compare-metadata.sh`. The comparison is normalised: object keys
   and the order of the entries of the downcall and resource lists are ignored, so a change in
   order or formatting passes with a note. Arrays of values are positional and are not sorted,
   so a changed `parameterTypes` order (a different native signature) is a real difference. A real
   content difference fails the run and prints a diff. The files and the diff are uploaded as the `metadata-drift`
   artifact and the report is in the job summary.
4. Reports newer versions with `scripts/check-updates.sh`: a newer Pi4J on Maven Central than
   `pi4j.version`, and a newer `bookworm-<version>` graalvm-pi-builder tag in GHCR than the pin.
   These never fail the run. A failed lookup is a warning and is marked "lookup incomplete" in the
   report: it is not read as "up to date", so it can neither open nor close the tracking issue.

**Tracking issue.** On scheduled runs, and on manual runs with the `open_issue` input ticked, the
workflow keeps one issue (found by its `metadata-drift` label, titled "Pi4J metadata: release or
version update needed") up to date with `scripts/update-tracking-issue.sh`. It is created when
the metadata differs or a newer version exists, its description is replaced with the latest
report on each run (no comment per run), it is reopened if the problem returns, and it is closed
when a run finds nothing to do with both version lookups complete. Pull request runs never touch it.

When the run fails because the metadata differs, a new metadata release is needed: bump the
metadata patch and release as described in [RELEASING.md](RELEASING.md).

The scripts can be run locally. For `compare-metadata.sh` use the generated file under
`metadata/target/generated-resources/META-INF/native-image/com.pi4j/pi4j-plugin-ffm/`;
`fetch-released-metadata.sh` accepts `RELEASED_JAR=<local jar>` instead of downloading, and
`update-tracking-issue.sh` has a `DRY_RUN=1` mode that prints the `gh` commands.

Limits: scheduled workflows only run from the default branch, so the schedule starts after the
first merge. The jar download needs the token to read packages; a pull request from a fork may
not get that permission, in which case the fetch step fails with a message saying so.

## Upgrading the GraalVM build environment

The container image used at build time has two tag forms:

| Tag | Meaning |
|---|---|
| `bookworm-graal25` | Mutable — always the latest GraalVM 25.x build; not used by default builds |
| `bookworm-25.5.5.0.3` | Version-pinned — specific build; the one pinned in `graalvm-pi-builder.env`, used by CI, releases and local builds |

### Minor GraalVM patch upgrade (e.g. 25.0.2 → 25.0.3)

1. Publish the `bookworm-25.0.3` tag in the `graalvm-pi-builder` repo.
2. Update `GRAALVM_PI_BUILDER_IMAGE` in [`graalvm-pi-builder.env`](graalvm-pi-builder.env), the
   single place the tag is pinned. Both workflows and `scripts/generate-metadata.sh` read it, so no
   workflow edit is needed, and the workflow cache key is derived from this value so it updates
   automatically.
3. If the captured downcall descriptors change, bump the metadata patch version in
   `metadata/pom.xml` and the parent `pom.xml`.

### Major GraalVM version bump (e.g. 25 → 26)

1. Build and publish `bookworm-graal26` / `bookworm-26.0.0` tags in `graalvm-pi-builder`.
2. Update `GRAALVM_PI_BUILDER_IMAGE` in [`graalvm-pi-builder.env`](graalvm-pi-builder.env); the
   cache key updates automatically.
3. Update `artifactId` in `metadata/pom.xml` from `pi4j-ffm-metadata-bookworm-graal25`
   to `pi4j-ffm-metadata-bookworm-graal26`.
4. Update all `graal25` references in `Readme.md` and `CLAUDE.md`.

## Project structure

```
pom.xml                          Parent POM (multi-module; not published)
probe/
  pom.xml                        Builds fat JAR via maven-shade; not published
  src/main/java/Probe.java       Instantiates the 5 *Native classes to trigger static init
  src/main/resources/
    agent-filter.json            Restricts agent capture to com.pi4j.plugin.ffm.**
scripts/
  run-probe.sh                   Builds probe JAR then runs generate-metadata.sh
  generate-metadata.sh           Runs the probe in the container with native-image-agent
metadata/
  pom.xml                        Zero-code JAR; metadata packaging only; published
  src/main/resources/
    META-INF/native-image/
      com.pi4j/pi4j-plugin-ffm/
        reachability-metadata.json  (generated at build time; not committed)
```

## How it works

A small `Probe` program instantiates all five Pi4J FFM `*Native` wrapper classes:

```java
new FileDescriptorNative();   // triggers FileDescriptorContext static init
new IoctlNative();            // triggers IoctlContext static init
new PollNative();             // triggers PollContext static init
new PermissionNative();       // triggers PermissionContext static init
new SMBusNative();            // triggers SMBusContext static init (requires libi2c)
```

Each `*Native` class extends a `*Context` class. The context class's static initialiser calls
`Linker.nativeLinker().downcallHandle()` for each Linux function it wraps. Running the probe
under `native-image-agent` intercepts all these calls and writes the JSON.

### Native functions captured

| Context class | Native functions |
|---|---|
| `FileDescriptorContext` | `open64`, `close`, `read`, `write`, `flock`, `access` |
| `IoctlContext` | `ioctl` (×3 signature variants) |
| `PollContext` | `poll` |
| `PermissionContext` | `setgrent`, `getgrent`, `endgrent`, `getgrouplist`, `getgrgid` |
| `SMBusContext` | `i2c_smbus_write_byte`, `i2c_smbus_read_byte`, `i2c_smbus_write_byte_data`, `i2c_smbus_read_byte_data`, `i2c_smbus_write_block_data`, `i2c_smbus_read_block_data`, `i2c_smbus_write_word_data`, `i2c_smbus_read_word_data` |

The base class `Pi4JNativeContext` also calls `strerror`, captured implicitly when any subclass
is loaded. In total, **21 unique downcall descriptors** are registered.
