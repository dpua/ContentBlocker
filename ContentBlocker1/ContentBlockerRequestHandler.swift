//
//  ContentBlockerRequestHandler.swift
//  ContentBlocker1
//
//  Created by ian on 16.03.2026.
//

import UIKit
import MobileCoreServices

class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {
    
    private let appGroupIdentifier = "group.com.ian.ContentBlocker"
    private let blockerIndex = 1

    func beginRequest(with context: NSExtensionContext) {
        let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier)
        let isEnabled = sharedDefaults?.bool(forKey: "blockersEnabled") ?? false
        
        var attachment: NSItemProvider
        
        if isEnabled {
            // Try to load from shared container first (for updated rules)
            if let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
                let sharedPath = sharedContainer.appendingPathComponent("blockerList\(blockerIndex).json")
                if FileManager.default.fileExists(atPath: sharedPath.path) {
                    attachment = NSItemProvider(contentsOf: sharedPath)!
                } else {
                    // Fall back to bundled rules
                    attachment = NSItemProvider(contentsOf: Bundle.main.url(forResource: "blockerList", withExtension: "json")!)!
                }
            } else {
                // Fall back to bundled rules
                attachment = NSItemProvider(contentsOf: Bundle.main.url(forResource: "blockerList", withExtension: "json")!)!
            }
        } else {
            // Return empty rules when disabled
            let emptyRules = "[]".data(using: .utf8)!
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("emptyRules.json")
            try? emptyRules.write(to: tempURL)
            attachment = NSItemProvider(contentsOf: tempURL)!
        }
        
        let item = NSExtensionItem()
        item.attachments = [attachment]
        
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
    
}
