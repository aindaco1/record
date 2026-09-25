import { ReviewedReportGroup } from './reviewed-report-group.js';
import { validateRecordReport, recordFingerprint, recordRelayReport } from './record-contract.mjs';
const adapter = {
    validate: validateRecordReport, fingerprint: recordFingerprint, relayReport: recordRelayReport,
    labels: report => `${report.kind === 'native_crash' ? 'crash' : 'diagnostic'},automated-report,needs-triage`,
    repository: 'record', failureCode: 'record_report_submission_failed'
};
export class RecordReportGroup extends ReviewedReportGroup {
    constructor(ctx, env, submit) { super(ctx, env, adapter, submit); }
}
