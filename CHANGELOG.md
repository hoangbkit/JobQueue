# Changelog

All notable changes to this project will be documented in this file.

## 1.0.0

Initial public release.

### Added

- Persistent job queue for iOS and macOS.
- Queue-wide and per-job-type concurrency limits.
- Priority-aware scheduling with fair rotation across job types.
- Scheduled and immediate job start policies.
- Queue-wide and per-job-type pause and resume controls.
- Cancellation, retry, removal, and edit-and-requeue support.
- Progress reporting and queue lifecycle events.
- Persistent job records with recovery after app relaunch.
- Persistence error reporting and recovery actions.
- Automatic cleanup of old terminal records.
- SwiftUI queue views and compact queue status controls.
- XcodeGen demo app targets for iOS and macOS.
- Fast and full GitHub Actions CI workflows.
