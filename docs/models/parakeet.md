# Parakeet model setup

Record uses Parakeet TDT v3 by default for on-device transcription. The model
is about 460 MB and is not bundled with Record. Recording remains available
when the model is absent; only transcription waits for setup.

## Download the Record model pack

Download the
[Record Parakeet v3 model pack](https://github.com/aindaco1/record/releases/download/v1.3.0/Record-Parakeet-v3-aed0274.zip)
(about 466 MB), then double-click the ZIP if your browser does not expand it
automatically.

The archive SHA-256 is
`c9089c5535e5518ec5f4e53074f120d4ce2675841bb0bacd541499f22b94fc9c`.
The
[separate checksum file](https://github.com/aindaco1/record/releases/download/v1.3.0/Record-Parakeet-v3-aed0274.zip.sha256)
is published beside the model pack.

The model pack contains only the 17 files accepted by Record's pinned manifest,
plus the upstream model card and attribution/license documents. The model files
come unmodified from the immutable publisher revision below. The pack is a
separate release asset; it is not stored in Git or bundled into `Record.app`.

## Import into Record

1. Open **Settings → Recording → Set Up Parakeet Model…**.
2. Choose **Import Downloaded Model…**.
3. Select either the expanded `Record-Parakeet-v3-aed0274` folder or its
   `parakeet-tdt-0.6b-v3` folder.

Record copies only its allowlisted model files. It rejects symbolic links,
missing files, wrong sizes, and SHA-256 mismatches. The verified copy is
installed atomically in Record's sandbox, so a failed import cannot replace a
working model. The downloaded ZIP and expanded folder can be deleted after a
successful import.

## Alternative: download from the verified publisher

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

Developers may instead run `./scripts/setup/install-parakeet-model.sh`, which
uses the same publisher and pinned revision.
