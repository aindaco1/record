# Shared support migration

Record 1.4.7 advances Platform to `b32a38b34f83daf142bd42d0c8f80ff4220952ad`, Desktop Swift 0.3.0 and Apple Support 0.1.0. Existing diagnostics imports continue through the compatibility facade. The app retains its exact Sparkle pin, report schema, preview, consent, endpoint, storage and error policy.

The transport and receipt implementations moved unchanged to a Foundation-only sibling package so Road Notice can share them. This app does not acquire iOS collection or background uploads. The app's source and license packaging include the sibling package. Product media, formatting and updater policy are unchanged.

Validation uses the app's existing tests and release gates, plus shared transport/receipt characterization. Hosted CI, signed artifacts and installed update acceptance are recorded separately in this migration's pull request and release evidence.

Rollback: revert this migration commit to restore Platform `fa7a8b3310819ce7d2c29f18b481966805bf2d1c` and Desktop Swift 0.2.0. No user-data or report schema migration is required.
