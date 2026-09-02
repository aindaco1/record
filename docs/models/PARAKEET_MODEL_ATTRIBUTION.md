# Parakeet v3 model-pack attribution

This model pack contains the Core ML files that Record uses for private,
on-device transcription. The model files are redistributed unmodified from:

- Publisher: FluidInference
- Model: `FluidInference/parakeet-tdt-0.6b-v3-coreml`
- Source: <https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml>
- Immutable source revision: `aed02740059203c4a87495924f685de3722ae9ce`
- Base model: `nvidia/parakeet-tdt-0.6b-v3`

The pinned Hugging Face metadata declares the model as licensed under the
[Creative Commons Attribution 4.0 International license](https://creativecommons.org/licenses/by/4.0/).
Its model card also contains an Apache License 2.0 statement; that model card
is included in the model pack as `UPSTREAM_MODEL_CARD.md` and remains available
at the immutable source revision above.

Record's packaging changes are limited to selecting the 17 files accepted by
Record's pinned manifest and removing repository metadata, caches, analytics
artifacts, and macOS Finder metadata. Model contents are not modified. Record
is not affiliated with or endorsed by FluidInference or NVIDIA.

Record verifies the size and SHA-256 digest of every accepted model file before
installing it. The downloadable archive is separate from `Record.app`; the app
does not download models or have a general network entitlement.
