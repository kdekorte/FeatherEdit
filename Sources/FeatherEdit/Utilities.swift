import AppKit
import ObjectiveC

/// Small helper so buttons can take a closure instead of target/action.
extension NSButton {
    func onAction(_ handler: @escaping () -> Void) {
        let proxy = ButtonActionProxy(handler: handler)
        target = proxy
        action = #selector(ButtonActionProxy.fire)
        associatedProxy = proxy
    }

    private static var proxyKey: UInt8 = 0
    private var associatedProxy: ButtonActionProxy? {
        get { objc_getAssociatedObject(self, &Self.proxyKey) as? ButtonActionProxy }
        set { objc_setAssociatedObject(self, &Self.proxyKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
}

private final class ButtonActionProxy: NSObject {
    let handler: () -> Void
    init(handler: @escaping () -> Void) {
        self.handler = handler
    }
    @objc func fire() {
        handler()
    }
}
