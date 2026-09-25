# Support

## Help and diagnostics

Choose **Help & diagnostics…** from the menu bar or **Settings… → General**.
Review the preview, optionally import a Record `.ips` crash log (up to 2 MiB),
and choose **Save report…** for a local JSON copy or **Send to public GitHub issues**.
Only the preview is sent. Opening the window, importing, refreshing and saving
never submit anything. A confirmed result offers **View GitHub issue**.

If delivery is not confirmed, retry the same preview, including after relaunch.
Refresh replaces the pending report and creates a new submission ID. Matching
reports join an existing issue. Raw incidents, recordings, transcripts, names,
paths and logs are excluded; see the [privacy policy](PRIVACY.md#reviewed-diagnostic-reports).

## Questions and bugs

Search [existing issues](https://github.com/aindaco1/record/issues) before
opening a new one. Include the Record version, macOS version, Mac model,
capture mode, permission state, and exact reproduction steps.

Use only synthetic or non-sensitive media when demonstrating a problem. Do not
attach screenshots, recordings, transcripts, model files, configuration
containing private paths, or anything from Record's app container.

For a failed session, describe the manifest state and sanitized log messages;
do not publish the session itself. The inspection commands in
[testing guide](testing.md) can collect structural information without
uploading content.

## Security issues

Do not open a public issue for a vulnerability. Follow the private reporting
instructions in [SECURITY.md](SECURITY.md).

## Scope

Record 1.x supports macOS 15+ on Apple Silicon. Intel Macs, older macOS
releases, cloud workflows, and third-party forks are outside the supported
matrix.
