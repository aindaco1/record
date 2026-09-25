import importlib.util
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('report_boundary', ROOT / 'scripts/ci/check-report-sender-boundary.py')
boundary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(boundary)


class ReportSenderBoundaryTests(unittest.TestCase):
    def test_fixed_boundary(self):
        boundary.validate(ROOT)

    def test_rejects_endpoint_validation_file_and_transport_expansion(self):
        mutations = [
            lambda s: s.replace('/v1/record/reports', '/v1/other/reports'),
            lambda s: s.replace('RecordDiagnosticReport.reviewed(bytes)', 'JSONDecoder().decode(RecordDiagnosticReport.self, from: bytes)'),
            lambda s: s + '\nlet store = FileManager.default\n',
            lambda s: s + '\nlet session = URLSession.shared\n',
        ]
        for mutate in mutations:
            with self.subTest(mutate=mutate), tempfile.TemporaryDirectory() as directory:
                root = pathlib.Path(directory)
                service = root / 'Sources/RecordReportSenderService'
                service.mkdir(parents=True)
                (service / 'main.swift').write_text(mutate((ROOT / 'Sources/RecordReportSenderService/main.swift').read_text()))
                core = root / 'Sources/RecordCore'
                core.mkdir()
                (core / 'RecordDiagnosticReport.swift').write_text((ROOT / 'Sources/RecordCore/RecordDiagnosticReport.swift').read_text())
                with self.assertRaises(AssertionError):
                    boundary.validate(root)
