# Third-party notices

Record preserves the MIT-licensed Git history of
[digimata/quill](https://github.com/digimata/quill). The repository's MIT
license remains in `LICENSE`.

Runtime Swift package dependencies and their licenses are recorded by
`Package.resolved` and their upstream repositories:

- Apple Swift Argument Parser — Apache License 2.0
- FluidAudio — Apache License 2.0
- Sparkle — permissive licenses reproduced from its upstream `LICENSE`

The assembled app includes the complete dependency licenses in
`Contents/Resources/Licenses`.

Record separately publishes an optional Parakeet v3 Core ML model pack for
local transcription. The model is not stored in Git or bundled into
`Record.app`. Its 17 model files are redistributed unmodified from
`FluidInference/parakeet-tdt-0.6b-v3-coreml` at immutable revision
`aed02740059203c4a87495924f685de3722ae9ce`; packaging removes unneeded model
repository files and adds the upstream model card and license notices. The
pinned Hugging Face metadata declares CC-BY-4.0, while the model card also
contains an Apache License 2.0 statement. The downloadable pack includes both
license texts and the attribution in `docs/models/PARAKEET_MODEL_ATTRIBUTION.md`.

The bundled screenshot shutter is the high-quality Freesound preview of
“camera shutter.wav” by mywhats, published under the Creative Commons CC0 1.0
public-domain dedication:

- source: https://freesound.org/people/mywhats/sounds/175517/
- source description: a Zenit-E analog-camera shutter
- bundled file: `Sources/Record/Resources/Shutter.mp3`
- bundled SHA-256: `fd2839e68a7787f849843116d6d4dea5aeef8f4d82419278a573200948aa3d91`
- bundled preview changes: Freesound's MP3 preview encoding; playback volume is
  reduced by Record at runtime

CC0 permits copying, modification, distribution, and performance, including
commercial use, without permission or attribution. The source and checksum are
retained here so the immutable bundled asset remains auditable.

[NewKap](https://github.com/MuntasirMalek/NewKap) and the locally installed Kap
plugins informed product behavior and architecture research. Before 1.4, Record
embedded NewKap's `static/menubarDefaultTemplate@2x.png` from commit
`33571acc90a1982acc125a669769adcbef8aa0de`. From 1.4, Record's application and
menu-bar icons both come from its own canonical `AppIcon.svg`. NewKap is
distributed under the following MIT license:

Copyright (c) Wulkano hello@wulkano.com (https://wulkano.com)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
