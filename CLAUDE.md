# CLAUDE.md — pi4j-graalvm-metadata

This repo produces a zero-code Maven JAR containing GraalVM `reachability-metadata.json`
for `com.pi4j:pi4j-plugin-ffm:4.0.0`. Without it, any Pi4J-based GraalVM native image fails
with `MissingForeignRegistrationError` because the `FunctionDescriptor` shapes passed to
`Linker.nativeLinker().downcallHandle()` are not registered at build time.

Adding the artifact as a Maven dependency is the only consumer action required — `native-image`
discovers the metadata automatically from the classpath.

Full background: `notes/pi4j-graalvm-metadata-project.md` (in the iron-j repo).

---

## Step progress

| Step | Status | Description |
|---|---|---|
| 1 | **Done** | Probe + metadata generation verified locally |
| 2 | **Done** | Maven pom.xml for `metadata` module; dynamic generation wired into build; publish config added |
| 3 | TODO | GitHub Actions workflow: probe → generate → publish |

---

## Maven coordinates

| Module | Artifact | Notes |
|---|---|---|
| Parent | `dev.lofthouse.pi4j:pi4j-ffm-metadata-parent:4.0.0-1:pom` | Not published |
| Probe | `dev.lofthouse.pi4j:pi4j-ffm-metadata-probe:4.0.0-1:jar` | Not published; internal build tool |
| **Metadata** | **`dev.lofthouse.pi4j:pi4j-ffm-metadata-bookworm-graal25:4.0.0-1:jar`** | Published artifact |

**Versioning:** `<pi4j-version>-<metadata-patch>`. GraalVM patch version is NOT in the Maven
version — it is encoded in the artifactId (`graal25` = GraalVM major 25.x.y).

---

## Container

| Purpose | Image |
|---|---|
| Local dev | `ghcr.io/lofthouse-dev/graalvm-pi-builder:latest` (built with `make build-dev`) |
| CI | `ghcr.io/lofthouse-dev/graalvm-pi-builder:bookworm-graal25` |

The container is `debian:bookworm` + GraalVM CE 25 + `libi2c-dev` + (previously JBang, now
unused for this project). Built in `graalvm-pi-builder/` in the iron-j repo.

---

## How to build the metadata JAR

```bash
mvn package
```

This builds the probe fat JAR, then the metadata module's build runs
`scripts/generate-metadata.sh` inside the container with `native-image-agent`. The captured
JSON lands in `metadata/target/generated-resources/` and is packaged directly into the JAR.
No manual copy step; nothing is committed.

To regenerate standalone (outside the Maven build):

```bash
bash scripts/run-probe.sh
```

Output: `generated-config/reachability-metadata.json` (gitignored).

---

## Project structure

```
pom.xml                          Parent POM (multi-module)
probe/
  pom.xml                        Depends on pi4j-plugin-ffm:4.0.0; builds fat JAR via shade
  src/main/java/Probe.java       Instantiates the 5 *Native classes to trigger static init
  src/main/resources/
    agent-filter.json            Restricts agent capture to com.pi4j.plugin.ffm.** (native-image-agent glob syntax, not regex)
scripts/
  run-probe.sh                   Builds probe JAR, runs in container with agent
metadata/
  pom.xml                        Zero-code JAR; packaging only
  src/main/resources/
    META-INF/native-image/
      com.pi4j/pi4j-plugin-ffm/
        reachability-metadata.json  (generated at build time; not committed)
```

---

## The 5 Context classes

| Context class | Package | Native functions | Notes |
|---|---|---|---|
| `FileDescriptorContext` | `common.file` | `open64`, `close`, `read`, `write`, `flock`, `access` | All with captureCallState except `access` |
| `IoctlContext` | `common.ioctl` | `ioctl` ×3 signature variants | |
| `PollContext` | `common.poll` | `poll` | |
| `PermissionContext` | `common.permission` | `setgrent`, `getgrent`, `endgrent`, `getgrouplist`, `getgrgid` | |
| `SMBusContext` | `common.i2c` | `i2c_smbus_write_byte`, `i2c_smbus_read_byte`, `i2c_smbus_write_byte_data`, `i2c_smbus_read_byte_data`, `i2c_smbus_write_block_data`, `i2c_smbus_read_block_data`, `i2c_smbus_write_word_data`, `i2c_smbus_read_word_data` | Uses `Pi4JArchitectureGuess.getLibraryPath("libi2c")` → `/usr/lib/aarch64-linux-gnu/libi2c.so` on aarch64 |

`Pi4JNativeContext` (base class of all five) has a `STR_ERROR` field that calls `strerror` —
captured implicitly when any subclass is loaded. This appears in the JSON as a `void*`-return,
`jint`-param descriptor without `captureCallState`.

Step 1 captured **21 unique downcall descriptors** (multiple functions share the same
FunctionDescriptor shape). The `resources` section contains two SLF4J entries — noise from
Pi4J's logging dependency, harmless for native-image.

---

## Open questions

- **agent-filter effectiveness for resources:** The two SLF4J resource entries in the captured
  JSON suggest the `access-filter-file` does not filter resource registrations (only class
  access/reflection). These entries are harmless but can be stripped manually if desired.
- **Maven Central:** GitHub Packages requires `read:packages` PAT for consumers. When adoption
  grows, publish to Maven Central via Sonatype OSSRH (requires artifact signing setup).

---

## Publishing (Step 2 / Step 3)

GitHub Packages initially. Consumers need in their `pom.xml`:

```xml
<repositories>
  <repository>
    <id>github-pi4j-graalvm-metadata</id>
    <url>https://maven.pkg.github.com/lofthouse-dev/pi4j-graalvm-metadata</url>
  </repository>
</repositories>

<dependency>
  <groupId>dev.lofthouse.pi4j</groupId>
  <artifactId>pi4j-ffm-metadata-bookworm-graal25</artifactId>
  <version>4.0.0-1</version>
</dependency>
```

Consumers also need a GitHub PAT with `read:packages` in their Maven `settings.xml`.
