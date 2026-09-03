# Security policy

## Supported versions

| Version | Security updates |
|---|---|
| 1.3.x | Yes |
| 1.2.x and earlier | No |

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for this repository. Do
not open a public issue for vulnerabilities involving privacy boundaries,
arbitrary code execution, permissions, signing, plugins, or recording data.

## Security invariants

- Screenshot pixels, media, transcripts, plugin state, and clipboard content
  remain local.
- Core product code does not contain analytics, cloud transcription, or upload
  clients.
- Completion hooks never invoke a shell and require absolute executables.
- Model inference requires verified local assets. A missing Parakeet model is
  downloaded only after explicit user action and must pass the pinned outer
  archive and per-file manifests before installation.
- Signed app artifacts keep the main process in App Sandbox without incoming
  or outgoing network entitlements. The dedicated model-downloader XPC has only
  sandbox and outbound-network entitlements, accepts no URL or path from the
  main process, and is independently checked by CI.
- A silent update check at launch and the explicit manual fallback use only
  Sparkle's sandboxed downloader service. Both the appcast and archive require
  Ed25519 signatures, and the archive also requires Developer ID signing and
  Apple notarization. Automatic installation and system profiling are disabled.
- FluidAudio is forced into offline mode before model preparation, and a test
  requires its network surface to fail with `networkDisabled`.
- Third-party extensions do not execute inside the capture process.
- Session metadata and derived artifacts use atomic writes.
- Release workflows use least-privilege permissions, protected environments,
  pinned action commits, Developer ID signing, notarization, signed update
  feeds, checksums, and provenance attestations.

Application permissions must be explained at the point of use. Do not log
captured content, transcript text, clipboard contents, credentials, or
security-scoped bookmark data.
