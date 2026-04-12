# pi4j-graalvm-metadata

GraalVM reachability metadata for `com.pi4j:pi4j-plugin-ffm:4.0.0`.

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
| **Metadata JAR** | `dev.lofthouse.pi4j:pi4j-ffm-metadata-bookworm-graal25:4.0.0-1` |

The artifactId encodes the capture environment: `bookworm` = Debian 12 (same glibc as
Raspberry Pi OS 12), `graal25` = GraalVM CE major version 25.

**Versioning scheme:** `<pi4j-version>-<metadata-patch>` — e.g. `4.0.0-1`. The GraalVM patch
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
    <version>4.0.0-1</version>
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
| **Container image** | `ghcr.io/lofthouse-dev/graalvm-pi-builder:bookworm-graal25` — pulled automatically on first run (local); CI pins to `bookworm-25.0.2` |

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

Set `GRAALVM_PI_BUILDER_IMAGE` to use a locally built image:

```bash
GRAALVM_PI_BUILDER_IMAGE=ghcr.io/lofthouse-dev/graalvm-pi-builder:latest mvn package
```

### Publishing

```bash
mvn deploy
```

Deploys the metadata JAR to GitHub Packages. Requires `GITHUB_TOKEN` or a PAT with
`write:packages` configured in `~/.m2/settings.xml` under the server id `github`.

## CI

Pull requests targeting `main` are built automatically via `.github/workflows/build.yml`.
The workflow can also be triggered manually via `workflow_dispatch`.

The CI build:
1. Installs Temurin 25 on the runner to compile the probe JAR.
2. Sets up QEMU binfmt for arm64 emulation (needed to run the arm64 container on x86_64).
3. Runs `mvn package` with `GRAALVM_PI_BUILDER_IMAGE` pinned to a version-specific container
   tag (`bookworm-25.0.2`) rather than the mutable `bookworm-graal25` tag, for reproducibility.
4. Caches both Maven dependencies and the container image between runs.

## Upgrading the GraalVM build environment

The container image used at build time has two tag forms:

| Tag | Meaning |
|---|---|
| `bookworm-graal25` | Mutable — always the latest GraalVM 25.x build; convenient for local dev |
| `bookworm-25.0.2` | Version-pinned — specific build; used by CI for reproducibility |

### Minor GraalVM patch upgrade (e.g. 25.0.2 → 25.0.3)

1. Publish the `bookworm-25.0.3` tag in the `graalvm-pi-builder` repo.
2. Update `GRAALVM_PI_BUILDER_IMAGE` in `.github/workflows/build.yml`; the workflow cache key
   is derived from this value so it updates automatically — no separate change needed.
3. If the captured downcall descriptors change, bump the metadata patch version in
   `metadata/pom.xml` and the parent `pom.xml`.

### Major GraalVM version bump (e.g. 25 → 26)

1. Build and publish `bookworm-graal26` / `bookworm-26.0.0` tags in `graalvm-pi-builder`.
2. Update `GRAALVM_PI_BUILDER_IMAGE` in `.github/workflows/build.yml`; the cache key updates automatically.
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
