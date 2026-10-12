//  SafariWebExtensionHandler.swift — Vision Font Extension
//  Answers browser.runtime.sendNativeMessage from background.js with the latest distance + settings that the
//  Vision Font app wrote to the shared store (see Shared/SharedStore.swift). Runs even when the app is closed;
//  it then reports appRunning=false and the app's last saved settings.

import Foundation
import SafariServices
import os

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private static let store = SharedStore()
    private static let log = Logger(subsystem: "com.bahacinar.VisionFont.Extension", category: "native")

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem
        let message = request?.userInfo?[SFExtensionMessageKey] as? [String: Any]

        let reply = NativeBridge.handle(message, store: Self.store)
        if let errors = reply["errors"] as? [String], !errors.isEmpty {
            Self.log.error("shared store: \(errors.joined(separator: "; "), privacy: .public)")
        }

        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: reply]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
