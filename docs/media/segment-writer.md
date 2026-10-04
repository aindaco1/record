# Hardware segment writer

`SegmentWriterPlan` maps validated capture settings to HEVC, AAC, and BT.709
AVFoundation settings. Its encoder specification requires hardware acceleration
instead of silently falling back to a CPU encoder. The real-time setting, 30/60
fps hint, disabled frame reordering, two-second keyframe interval, and bounded
4-50 Mbps rate are explicit and unit tested.

`AVAssetSegmentWriter` owns one segment interval with independent writers for
video-only QuickTime and each enabled AAC/CAF audio source. When
an input is not ready, the processor reports writer backpressure to the bounded
ingress instead of blocking or allocating another queue.

Each source is written to a unique hidden partial file in the destination
directory. Successful AVAssetWriter finalization is followed by a same-volume
rename to the requested `.mov` or `.caf`. Existing final files are never overwritten.
A failed promotion preserves the finalized partial for recovery; setup, encode,
and mux failures remove only their incomplete partial file. Previously finalized
segments are untouched.

Regular CI validates settings, state behavior, path safety, and empty-segment
cleanup without requesting capture permission. Real hardware encoding, disk
pressure, forced termination, sustained 4K60 throughput, and media inspection
remain part of the dedicated Apple Silicon hardware matrix.
