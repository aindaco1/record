"""Fail closed on expansion of the reviewed helper's tiny fixed-endpoint adapter."""
import pathlib
import re
import sys


def require(condition, message="invalid report sender boundary"):
    if not condition:
        raise AssertionError(message)


def validate(root):
    source = root / 'Sources/RecordReportSenderService'
    files = list(source.rglob('*.swift'))
    require({p.name for p in files} == {'main.swift'}, 'unexpected report sender source')
    text = files[0].read_text()
    urls = re.findall(r'https?://[^"\s]+', text)
    require(urls == ['https://crash.dustwave.xyz/v1/record/reports'], 'report endpoint changed')
    require('RecordDiagnosticReport.reviewed(bytes)' in text, 'missing input validation')
    require(text.index('RecordDiagnosticReport.reviewed(bytes)') < text.index('ReviewedReportClient().send('))
    require(text.count('ReviewedReportClient().send(') == 1, 'unexpected send path')
    forbidden = r'URLSession|URLRequest|URLComponents|FileManager|FileHandle|Process\(|fileURL|contentsOf:|UserDefaults|NSWorkspace|\b(?:open|fopen|socket|connect|getaddrinfo)\s*\('
    require(not re.search(forbidden, text), 'general networking, file or process access in sender')
    require(set(re.findall(r'^import (\w+)', text, re.M)) == {'Foundation', 'DustWaveDiagnostics', 'RecordCore'})
    protocol = (root / 'Sources/RecordCore/RecordDiagnosticReport.swift').read_text().split('@objc public protocol')[1]
    require(re.findall(r'func (\w+)', protocol) == ['sendReviewedReport'], 'expanded XPC interface')
    require('(_ bytes: Data, withReply reply: @escaping (Data?, NSError?) -> Void)' in protocol)
    print('reviewed report sender boundary passed')


if __name__ == '__main__':
    validate(pathlib.Path(sys.argv[1]))
