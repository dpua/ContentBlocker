//
//  ContentBlockerRequestHandler.swift
//  ContentBlocker2
//
//  Created by ian on 16.03.2026.
//

import UIKit
import MobileCoreServices

class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        // Check if blockers are enabled
        let isEnabled = UserDefaults.standard.bool(forKey: "blockersEnabled")
        
        var attachment: NSItemProvider
        
        if isEnabled {
            // Try to load from shared container first (for updated rules)
            if let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.ian.ContentBlocker") {
                let sharedPath = sharedContainer.appendingPathComponent("blockerList2.json")
                if FileManager.default.fileExists(atPath: sharedPath.path) {
                    attachment = NSItemProvider(contentsOf: sharedPath)!
                } else {
                    attachment = NSItemProvider(contentsOf: Bundle.main.url(forResource: "blockerList", withExtension: "json"))!
                }
            } else {
                attachment = NSItemProvider(contentsOf: Bundle.main.url(forResource: "blockerList", withExtension: "json"))!
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
