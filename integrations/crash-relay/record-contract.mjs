// Record owns this strict public projection. The relay copy must remain byte-identical.
export const schema = 'record-diagnostic-v1';
export const events = ['launch','recordingRequested','recordingStopped','pauseResumeRequested','screenshotSaved','screenshotFailed','shortcutUnavailable'];
const images = ['record','Record','Sparkle','AppKit','SwiftUI','SwiftUICore','ScreenCaptureKit','AVFoundation','CoreMedia','VideoToolbox','libswiftCore.dylib','libsystem_kernel.dylib'];
const signals = ['SIGABRT','SIGSEGV','SIGBUS','SIGILL','SIGTRAP','SIGKILL','SIGFPE','SIGTERM','SIGPIPE'];
const exceptions = ['EXC_BAD_ACCESS','EXC_BAD_INSTRUCTION','EXC_ARITHMETIC','EXC_SOFTWARE','EXC_BREAKPOINT','EXC_CRASH','EXC_RESOURCE','EXC_GUARD'];
const version = /^[0-9]{1,8}(?:\.[0-9]{1,8}){0,3}$/;
function requireValue(ok) { if (!ok) throw new TypeError('Invalid Record diagnostic report'); }
function object(value, keys) { requireValue(value && typeof value === 'object' && !Array.isArray(value) && Object.keys(value).every(k => keys.includes(k))); }
function integer(value, max) { requireValue(Number.isInteger(value) && value >= 0 && value <= max); }
function choice(value, values) { requireValue(values.includes(value)); }
function versions(value) { for (const k of ['version','build','operatingSystem']) requireValue(typeof value[k] === 'string' && version.test(value[k])); }
export function validateRecordReport(r) {
    object(r,['schema','id','kind','application','state','crash']);
    requireValue(r.schema === schema && typeof r.id === 'string' && /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(r.id));
    choice(r.kind,['current_state','native_crash']);
    object(r.application,['version','build','operatingSystem','architecture']); versions(r.application); requireValue(r.application.architecture === 'arm64');
    const s = r.state;
    object(s,['activity','screenSource','transcription','transcriptCleanup','modelSetupInProgress','events']);
    for (const k of ['transcriptCleanup','modelSetupInProgress']) requireValue(typeof s[k] === 'boolean');
    choice(s.activity,['idle','busy','screenRecording','audioRecording','paused']);
    choice(s.screenSource,['mainDisplay','systemPicker','region']);
    choice(s.transcription,['disabled','parakeet','macwhisper']);
    requireValue(Array.isArray(s.events) && s.events.length <= 20); s.events.forEach(e => choice(e,events));
    if (r.kind === 'native_crash') {
        const c = r.crash;
        object(c,['exception','signal','image','imageOffset','version','build','operatingSystem']); versions(c); choice(c.exception,exceptions);
        if (c.signal !== undefined) choice(c.signal,signals);
        if (c.image !== undefined) choice(c.image,images);
        if (c.imageOffset !== undefined) integer(c.imageOffset,1e9);
        requireValue((c.image === undefined) === (c.imageOffset === undefined));
        for (const k of ['version','build','operatingSystem']) requireValue(c[k] === r.application[k]);
    } else requireValue(r.crash === undefined);
    requireValue(new TextEncoder().encode(JSON.stringify(r)).length <= 8192);
    return r;
}
export async function recordFingerprint(input) {
    const r = validateRecordReport(input), s = r.state, c = r.crash;
    const grouping = r.kind === 'native_crash'
        ? { product:'record',kind:r.kind,exception:c.exception,signal:c.signal??null,image:c.image??null,imageOffset:c.imageOffset??null,build:c.build,operatingSystem:c.operatingSystem }
        : { product:'record',kind:r.kind,activity:s.activity,screenSource:s.screenSource,transcription:s.transcription,
            failure:[...s.events].reverse().find(e => ['screenshotFailed','shortcutUnavailable'].includes(e)) ?? 'none' };
    const hash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify(grouping)));
    return [...new Uint8Array(hash)].map(v => v.toString(16).padStart(2,'0')).join('').slice(0,20);
}
export function recordRelayReport(input) {
    const r = validateRecordReport(input);
    return { app:{name:'Record',identifier:'com.aindaco.record',version:r.application.version,buildProfile:r.application.build,os:`macos ${r.application.operatingSystem}`,arch:'arm64',channel:'production'},
        report:{id:r.id,kind:r.kind,surface:r.kind==='native_crash'?'native':'capture',message:r.crash?.exception??'Reviewed Record state',stack:'',capturedAt:new Date().toISOString(),context:{recordDiagnostics:r}} };
}
