/// Shared constants for the HTML template contract.
/// These must stay in sync with template.html — the template contract test verifies this.
public enum TemplateConstants {
    /// Placeholder in template.html replaced with rendered markdown body.
    public static let contentPlaceholder = "{{CONTENT}}"

    /// Element ID for the main content article. Used by:
    /// - template.html: `<article id="content">`
    /// - WebPreviewView: JS fast-path innerHTML swap via getElementById
    public static let contentElementID = "content"

    /// Element ID for the settings CSS override style tag. Used by:
    /// - WebPreviewView: injectSettingsCSS creates `<style id="settings-override">`
    /// - WebPreviewView: JS fast-path updates textContent of this element
    public static let settingsStyleID = "settings-override"

    /// WKWebView message handler name for scroll sync. Used by:
    /// - WebPreviewView: registers handler with this name
    /// - scrollListenerJS: posts messages to this handler
    public static let scrollSyncHandler = "scrollSync"

    /// WKWebView message handler name for render completion. Posted (once per load,
    /// gated by window._renderCompletePosted) from the same sites that set the
    /// window.rendered sentinel: mermaid .then/.catch (HTMLPipeline.injectMermaid)
    /// and the template.html timeout fallback. WebPreviewView drives scroll-listener
    /// install + position restore off this signal instead of asyncAfter timers.
    public static let renderCompleteHandler = "renderComplete"
}
