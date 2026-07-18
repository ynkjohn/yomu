# ADR 0001 — Yomu owns a replaceable reading-engine boundary

- Status: Accepted
- Date: 2026-07-18

## Context

Yomu is the product, but its desktop UI and local Core currently receive
`SuwayomiApi`, protocol DTOs, process lifecycle and vendor terminology. The
engine already runs as a Yomu-managed loopback process and owns the approved
reading facts, yet the visible coupling makes the application feel like a
client that asks the user to administer a server.

## Decision

- Yomu owns a replaceable reading-engine boundary expressed with Yomu models
  and narrow capabilities.
- Suwayomi remains the internal implementation for extension execution,
  catalog, library, chapters, pages, progress, downloads and extension state.
- The desktop remains a native Flutter Windows application. Integration does
  not require a single operating-system process.
- The engine process remains isolated on `127.0.0.1:14567`; Yomu Core remains
  on `127.0.0.1:8787` by default and is the only LAN/PWA surface.
- Protocol DTOs, GraphQL/REST details, Java, JAR, PID, process ownership and
  vendor-specific policy stay inside `yomu_suwayomi` and diagnostics.
- UI and Yomu Core receive only the capabilities required by their current
  vertical slice. `YomuReadingEngine` is only a composition-root aggregate.
- Media crosses the boundary as an opaque `MediaReference`; consumers never
  receive the engine loopback URL or transport path.
- Product readiness is distinct from HTTP reachability. A ready engine must
  also have valid artifacts, safe ownership, compatible protocol/capabilities
  and the expected data root.
- Lifecycle becomes automatic, ownership-safe and retry-limited. Operational
  timing values are centralized policies, not architectural constants.
- Shutdown drains admitted mutations and progress writes. Downloads join that
  drain only after a real upstream proof confirms preservation of queue, state
  and files.
- Release distribution contains the already-pinned JRE and JAR and does not
  download the engine on first use. Temurin redistribution follows GPLv2
  section 3(a): the exact OpenJDK source, Temurin build source and provenance
  are separate assets in the same release download location as the Yomu
  portable ZIP. Suwayomi exact source is published there as well. A fail-closed
  gate inspects the ZIP and verifies the complete set before publication.
  Installer formats remain blocked until a format-specific content gate exists.
  Artifact versions are changed only in a separately approved update.
- Sensitive Maya actions continue to require `ActionProposal` and explicit
  confirmation; the reading engine gains no autonomous authority.
- The migration is incremental. A capability is introduced only when a real
  consumer is migrated.

## Data ownership

Suwayomi continues to own catalog metadata, library membership, chapters,
pages, reading progress, read flags, downloads and extension state. Yomu
SQLite remains schema v5 and owns only application-specific data: app metadata,
session hashes, Maya history/proposals and non-secret provider configuration.
This decision creates no new persistence or migration.

## Consequences

Positive consequences are a product-native experience, smaller fakes, tests
without a JVM for most consumers, sanitized errors and a replaceable adapter
boundary while preserving the existing extension ecosystem and process fault
isolation.

Costs are duplicated domain mapping, an offline bundle containing a JRE and
JAR, a more explicit lifecycle supervisor and continued responsibility for
compatibility and upstream security updates.

## Alternatives rejected for this phase

- A maintained fork: recurring merge, release and security cost without a
  demonstrated upstream blocker.
- A deep fork or custom protocol: larger divergence and data-compatibility risk.
- A Yomu-native extension runtime: extreme implementation and compatibility
  cost.
- An in-process JVM: weaker fault isolation and no measured performance benefit.

Each alternative requires its own ADR and explicit approval before adoption.

## Outside this decision

This ADR does not authorize tray/background behavior, a final installer
technology, independent engine updates, a dynamic engine port, simultaneous
multiple engines, universal identifiers, new data owners, new persistence,
definitive timeout/retry/log-retention values or “Novidades desktop”.

## Validation

The decision is implemented only when common UI and Yomu Core no longer import
the concrete API or protocol DTOs, the boundary guard prevents regressions,
`/api/v1` and media proxy behavior remain compatible, public errors are
sanitized, the pinned offline bundle and real compatibility probe pass, and
auto-start/recovery/shutdown tests demonstrate no duplicate or orphan engine
process. Data ownership and Yomu schema v5 must remain unchanged.

## Revisit when

Revisit this decision if upstream stops resolving critical defects, its
protocol blocks an essential requirement, extension incompatibility becomes
recurring, redistribution is legally blocked, measurements prove the process
boundary is a material bottleneck, or a second implementation demonstrates a
real need to expand the contracts.
