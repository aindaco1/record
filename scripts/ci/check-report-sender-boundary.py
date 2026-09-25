"""Fail closed on expansion of the reviewed helper's tiny fixed-endpoint adapter."""
import pathlib
import re
import sys


def validate(root):
    source = root / 'Sources/RecordReportSenderService'
    files = list(source.rglob('*.swift'))
    assert {p.name for p in files} == {'main.swift'}, 'unexpected report sender source'
    text = files[0].read_text()
    urls = re.findall(r'https?://[^"\s]+', text)
    assert urls == ['https://crash.dustwave.xyz/v1/record/reports'], 'report endpoint changed'
    assert 'RecordDiagnosticReport.reviewed(bytes)' in text, 'missing input validation'
    assert text.index('RecordDiagnosticReport.reviewed(bytes)') < text.index('ReviewedReportClient().send(')
    assert text.count('ReviewedReportClient().send(') == 1, 'unexpected send path'
    forbidden = r'URLSession|URLRequest|URLComponents|FileManager|FileHandle|Process\(|fileURL|contentsOf:|UserDefaults|NSWorkspace|\b(?:open|fopen|socket|connect|getaddrinfo)\s*\('
    assert not re.search(forbidden, text), 'general networking, file or process access in sender'
    assert set(re.findall(r'^import (\w+)', text, re.M)) == {'Foundation', 'DustWaveDiagnostics', 'RecordCore'}
    protocol = (root / 'Sources/RecordCore/RecordDiagnosticReport.swift').read_text().split('@objc public protocol')[1]
    assert re.findall(r'func (\w+)', protocol) == ['sendReviewedReport'], 'expanded XPC interface'
    assert '(_ bytes: Data, withReply reply: @escaping (Data?, NSError?) -> Void)' in protocol
    print('reviewed report sender boundary passed')


if __name__ == '__main__':
    validate(pathlib.Path(sys.argv[1]))
