# Parakeet model setup

Record uses Parakeet TDT v3 by default for on-device transcription. The model
is about 460 MB and is not bundled with Record. Recording remains available
when the model is absent; only transcription waits for setup.

## Download from the verified publisher

The approved model is
[FluidInference/parakeet-tdt-0.6b-v3-coreml](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/tree/aed02740059203c4a87495924f685de3722ae9ce)
at immutable revision `aed02740059203c4a87495924f685de3722ae9ce`. Its model
card declares the CC-BY-4.0 license.

Install the Hugging Face CLI outside Record, then download only the files that
Record needs:

```sh
hf download FluidInference/parakeet-tdt-0.6b-v3-coreml \
  --revision aed02740059203c4a87495924f685de3722ae9ce \
  --local-dir "$HOME/Downloads/parakeet-tdt-0.6b-v3" \
  --include \
  'Preprocessor.mlmodelc/*' \
  'Encoder.mlmodelc/*' \
  'Decoder.mlmodelc/*' \
  'JointDecisionv3.mlmodelc/*' \
  'parakeet_vocab.json'
```

Do not download a similarly named model from another account or omit the
revision. Record deliberately does not run a model downloader or receive a
network entitlement.

## Import into Record

1. Open **Transcription Model → Set Up Parakeet Model…**.
2. Choose **Import Downloaded Model…**.
3. Select `$HOME/Downloads/parakeet-tdt-0.6b-v3`.

Record copies only its allowlisted model files. It rejects symbolic links,
missing or unexpected files, wrong sizes, and SHA-256 mismatches. The verified
copy is installed atomically in Record's sandbox, so a failed import cannot
replace a working model. The downloaded source folder can be deleted after a
successful import.

Developers may instead run `./scripts/setup/install-parakeet-model.sh`, which
uses the same publisher and pinned revision.
