(keys | sort) == [
  "appVersion", "buildAppSHA256", "buildNumber", "bundleCheckSHA256",
  "commit", "executableSHA256", "modelDownloaderExecutableSHA256",
  "modelDownloaderInfoPlistSHA256", "packageResolvedSHA256", "repository",
  "runAttempt", "runID", "runner", "schema", "sourceInfoPlistSHA256",
  "stampAppSHA256", "workflow", "xcodeBuild", "xcodeVersion"
] and
.schema == "record-ci-app-v3" and
.repository == $repository and .commit == $commit and
.workflow == ".github/workflows/ci.yml" and
.runID == $runID and .runAttempt == $runAttempt and
.runner == "github-hosted" and .xcodeVersion == "Xcode 27.0" and
.xcodeBuild == "27A266a" and
.appVersion == "0.0.0-ci" and
(.buildNumber | test("^[1-9][0-9]*$")) and
([
  .packageResolvedSHA256, .buildAppSHA256, .stampAppSHA256,
  .bundleCheckSHA256, .sourceInfoPlistSHA256, .executableSHA256,
  .modelDownloaderInfoPlistSHA256, .modelDownloaderExecutableSHA256
] | all(type == "string" and test("^[a-f0-9]{64}$")))
