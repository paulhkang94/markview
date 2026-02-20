@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation

/// Thin wrapper around C-level AXUIElement accessibility functions.
/// Provides element discovery, attribute access, actions, and keyboard simulation.
enum AXHelper {

    // MARK: - Errors

    enum AXError: Error, CustomStringConvertible {
        case timeout(String)
        case elementNotFound(String)
        case actionFailed(String)

        var description: String {
            switch self {
            case .timeout(let msg): return "Timeout: \(msg)"
            case .elementNotFound(let msg): return "Element not found: \(msg)"
            case .actionFailed(let msg): return "Action failed: \(msg)"
            }
        }
    }

    // MARK: - Element Discovery

    static func appElement(pid: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    static func windows(of app: AXUIElement) -> [AXUIElement] {
        attribute(app, kAXWindowsAttribute) ?? []
    }

    /// Recursively find an element matching role and optional title.
    static func findElement(root: AXUIElement, role: String, title: String? = nil) -> AXUIElement? {
        if let currentRole: String = attribute(root, kAXRoleAttribute) {
            if currentRole == role {
                if let title = title {
                    if let currentTitle: String = attribute(root, kAXTitleAttribute),
                       currentTitle.localizedCaseInsensitiveContains(title) {
                        return root
                    }
                } else {
                    return root
                }
            }
        }

        for child in children(root) {
            if let found = findElement(root: child, role: role, title: title) {
                return found
            }
        }
        return nil
    }

    /// Find element by role and accessibility identifier (description).
    static func findElement(root: AXUIElement, role: String, identifier: String) -> AXUIElement? {
        if let currentRole: String = attribute(root, kAXRoleAttribute),
           currentRole == role {
            if let desc: String = attribute(root, kAXDescriptionAttribute),
               desc.localizedCaseInsensitiveContains(identifier) {
                return root
            }
            if let id: String = attribute(root, kAXIdentifierAttribute),
               id == identifier {
                return root
            }
        }

        for child in children(root) {
            if let found = findElement(root: child, role: role, identifier: identifier) {
                return found
            }
        }
        return nil
    }

    /// Collect all elements with the given role.
    static func allElements(root: AXUIElement, role: String) -> [AXUIElement] {
        var results: [AXUIElement] = []
        collectElements(root: root, role: role, into: &results)
        return results
    }

    private static func collectElements(root: AXUIElement, role: String, into results: inout [AXUIElement]) {
        if let currentRole: String = attribute(root, kAXRoleAttribute),
           currentRole == role {
            results.append(root)
        }
        for child in children(root) {
            collectElements(root: child, role: role, into: &results)
        }
    }

    // MARK: - Attribute Access

    static func attribute<T>(_ element: AXUIElement, _ attr: String) -> T? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attr as CFString, &value)
        guard result == .success else { return nil }
        return value as? T
    }

    static func attribute(_ element: AXUIElement, _ attr: String) -> [AXUIElement] {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attr as CFString, &value)
        guard result == .success, let array = value as? [AXUIElement] else { return [] }
        return array
    }

    static func value(_ element: AXUIElement) -> String? {
        attribute(element, kAXValueAttribute)
    }

    static func title(_ element: AXUIElement) -> String? {
        attribute(element, kAXTitleAttribute)
    }

    static func role(_ element: AXUIElement) -> String? {
        attribute(element, kAXRoleAttribute)
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute)
    }

    static func subrole(_ element: AXUIElement) -> String? {
        attribute(element, kAXSubroleAttribute)
    }

    // MARK: - Actions

    static func press(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }

    static func setValue(_ element: AXUIElement, _ val: Any) {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, val as CFTypeRef)
    }

    static func setFocus(_ element: AXUIElement) {
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)
    }

    /// Get the size of an AX element (window, view, etc).
    static func size(_ element: AXUIElement) -> CGSize? {
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    /// Get the position of an AX element.
    static func position(_ element: AXUIElement) -> CGPoint? {
        var posValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success else { return nil }
        var pos = CGPoint.zero
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &pos) else { return nil }
        return pos
    }

    // MARK: - Keyboard (via CGEvent)

    static func typeText(_ text: String) {
        for char in text.unicodeScalars {
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            var utf16 = [UniChar(char.value)]
            keyDown?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &utf16)
            keyUp?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &utf16)
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    static func keyPress(_ keyCode: CGKeyCode, modifiers: CGEventFlags = []) {
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = modifiers
        keyUp?.flags = modifiers
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
    }

    // Common key codes
    private static let kVK_ANSI_S: CGKeyCode = 0x01
    private static let kVK_ANSI_E: CGKeyCode = 0x0E
    private static let kVK_ANSI_F: CGKeyCode = 0x03
    private static let kVK_ANSI_O: CGKeyCode = 0x1F
    private static let kVK_ANSI_Equal: CGKeyCode = 0x18
    private static let kVK_ANSI_Minus: CGKeyCode = 0x1B
    private static let kVK_ANSI_0: CGKeyCode = 0x1D

    static func cmdS() { keyPress(kVK_ANSI_S, modifiers: .maskCommand) }
    static func cmdE() { keyPress(kVK_ANSI_E, modifiers: .maskCommand) }
    static func cmdF() { keyPress(kVK_ANSI_F, modifiers: .maskCommand) }
    static func cmdO() { keyPress(kVK_ANSI_O, modifiers: .maskCommand) }
    static func cmdPlus() { keyPress(kVK_ANSI_Equal, modifiers: .maskCommand) }
    static func cmdMinus() { keyPress(kVK_ANSI_Minus, modifiers: .maskCommand) }
    static func cmdZero() { keyPress(kVK_ANSI_0, modifiers: .maskCommand) }

    // MARK: - Waiter (Poll-Based)

    /// Poll until condition returns true, or throw on timeout.
    static func waitFor(
        timeout: TimeInterval = 5.0,
        interval: TimeInterval = 0.1,
        description: String = "condition",
        condition: () -> Bool
    ) throws {
        let deadline = CFAbsoluteTimeGetCurrent() + timeout
        while CFAbsoluteTimeGetCurrent() < deadline {
            if condition() { return }
            Thread.sleep(forTimeInterval: interval)
            // Pump the run loop to process events
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        throw AXError.timeout("Timed out waiting for \(description) after \(timeout)s")
    }

    // MARK: - Permission Check

    static func isAccessibilityEnabled() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
