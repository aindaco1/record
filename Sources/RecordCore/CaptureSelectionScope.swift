/// `SCContentFilter.style` describes whether a stream is display-bound, which
/// need not mean the person selected every application on that display.
public enum CaptureSelectionScope {
    /// Nil inclusion flags mean the operating system cannot expose the filter's
    /// scope. Never treat an ambiguous display-bound filter as a whole display.
    public static func resolve(
        reportedStyle: CaptureSelectionStyle,
        includesApplications: Bool?,
        includesWindows: Bool?
    ) -> CaptureSelectionStyle? {
        guard reportedStyle == .display else { return reportedStyle }
        guard let includesApplications, let includesWindows else { return nil }
        if includesApplications { return .application }
        if includesWindows { return .window }
        return .display
    }
}
