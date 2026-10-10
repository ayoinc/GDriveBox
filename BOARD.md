# GDriveBox Kanban Board

Source of truth for work on GDriveBox. Walk it right-to-left (Done → Blocked) at the start of every session.

## Policies

| Policy | Rule |
|---|---|
| WIP: In Progress | **2** — set by the team 2026-10-10. Hypothesis: re-measure after two weeks. |
| WIP: Verify | **2** — matches In Progress (Jev abstained 2 vs 1 at 0.64; revisit with data). |
| WIP: Expedite | **1**, bypasses other limits. |
| Blocked lane | Cards waiting on an external action. Excluded from WIP. Each names its owner and unblock condition. |
| Classes of service | **Expedite**: crisis only (data loss, token leak, broken sync for users). **Standard**: default, FIFO. **Intangible**: CI, tooling, docs; pulled only when no Standard card is Ready. |
| Pull order | Expedite → Standard (FIFO) → Intangible. |
| Definition of Ready | Acceptance criteria written; no unresolved external dependency. |
| Definition of Done | `swift build` and `swift test` pass; the changed behavior was exercised by a smoke run (or the card states which part is blocked and why); board updated; Jev acceptance check returns act/review. |
| Decisions | Ask Jev first at every decision point. Abstains go to the human. |

Cycle time = Done date − Started date (calendar days). Track it per class.

## Open decisions (Jev abstained → human)

| Decision | Jev lean | Where it lands |
|---|---|---|
| Verify WIP limit 2 vs 1 | 2 (0.64) | Policy above; revisit with two weeks of data. |
| Sign-in reuses the Safari Google session vs. a private (ephemeral) session | reuse (0.64) | `GoogleSignInFlow.signIn(prefersEphemeralSession:)`; choose in S-06. |
| Commit each card to git when it reaches Done | no lean (0.48) | Nothing committed yet; the human decides. |

## Done

| Card | Class | Started | Done |
|---|---|---|---|
| S-01 Repo bootstrap | Standard | 2026-10-10 | 2026-10-10 |
| S-02 DriveAPI client — 10 Swift Testing tests (incl. 11-case retry classification); live smoke vs `www.googleapis.com` (real 401 parsed, single forced refresh). Authenticated listing exercised in S-06 (needs B-03). | Standard | 2026-10-10 | 2026-10-10 |
| S-03 DriveAuth — 8 Swift Testing tests (stubbed token endpoint through AppAuth's HTTP stack); smoke: login-keychain round trip, unsigned data-protection keychain → `-34018`, refresh against real `oauth2.googleapis.com` surfaces `invalid_client`. Interactive passkey/MFA sign-in and a successful real refresh exercised in S-06 (needs B-01, B-03). | Standard | 2026-10-10 | 2026-10-10 |

## Verify

_(empty)_

## In Progress (WIP 2)

_(empty)_

## Ready

_(empty — remaining Milestone 1 cards are blocked)_

## Backlog

### Milestone 1 — sign in + list My Drive
- **S-05 Xcode project (XcodeGen)** · Standard · needs B-01, B-02
  - AC: `project.yml` with menu-bar app + File Provider extension; arm64 only; macOS 15; App Group + keychain group; links SyncCore by path.
- **S-06 Menu-bar sign-in + debug listing** · Standard · needs B-01, B-03, S-05
  - AC: sign in once with a passkey and once with another MFA method; a real token refresh succeeds; debug window lists My Drive root; choose the ephemeral-session setting.

### Milestone 2+
- **S-04 MetadataStore** · Standard — GRDB SQLite (WAL) in the App Group: items, sync_state (changes pageToken), uploads.
- **S-07 File Provider domain + folder enumeration** · Standard
- **S-08 On-demand download (`fetchContents`)** · Standard
- **S-09 Uploads + create/modify/delete** · Standard — multipart ≤ 5 MB, resumable above; delete → Drive Trash.
- **S-10 Remote change polling** · Standard — 60 s + wake/network/activation; extension alone advances the pageToken.
- **S-11 Conflicts: keep both** · Standard
- **S-12 Onboarding, status, sign out (revoke)** · Standard
- **S-13 Release pipeline** · Standard — Developer ID, notarization, Sparkle, Homebrew cask (arm64, macOS ≥ 15).
- **I-01 CI** · Intangible — GitHub Actions `swift build` + `swift test` on an Apple-silicon runner.
- **I-02 README + CONTRIBUTING** · Intangible
- **I-03 swift-format config** · Intangible
- **I-04 Test-build flake** · Intangible — with Command Line Tools only, `swift test` (default `swiftbuild` backend) alternates: one run fails with "plugin for module 'TestingMacros' not found", the next passes. `--build-system native` cannot find `Testing` at all. Workaround: re-run. Re-check once Xcode is installed (B-01).

## Blocked (owner: human)

- **B-01 Install Xcode** — only Command Line Tools are installed. Unblocks S-05.
- **B-02 Apple Developer Program** — Team ID, App Group, keychain access group. Unblocks S-05 signing and running the extension.
- **B-03 Google Cloud OAuth client** — project, enable Drive API, External consent screen (Testing), iOS-type OAuth client → client ID. Unblocks S-06.
- **B-04 Google restricted-scope verification** — homepage, privacy policy, demo video, "Backup and sync" justification. Unblocks public release (Testing mode: 100 users, 7-day refresh tokens).
