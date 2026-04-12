# CLAUDE.md — pi4j-graalvm-metadata

For a full description of the project — what it does, why, prerequisites, build instructions,
and consumption — see [Readme.md](Readme.md).

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
