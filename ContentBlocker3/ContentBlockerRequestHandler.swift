//
//  ContentBlockerRequestHandler.swift
//  ContentBlocker3
//
//  Created by ian on 16.03.2026.
//

import UIKit
import MobileCoreServices
import UniformTypeIdentifiers

class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {
    
    private let appGroupIdentifier = "group.com.ian.ContentBlocker"
    private let blockerIndex = 3

    func beginRequest(with context: NSExtensionContext) {
        // Check if shared defaults exist and read enabled state
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            // App Group not configured - fall back to bundled rules
            returnBundledRules(context: context)
            return
        }
        
        let isEnabled = sharedDefaults.bool(forKey: "blockersEnabled")
        
        if isEnabled {
            returnActiveRules(context: context)
        } else {
            returnEmptyRules(context: context)
        }
    }
    
    private func returnActiveRules(context: NSExtensionContext) {
        // Try to load from shared container first (for updated rules)
        if let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let sharedPath = sharedContainer.appendingPathComponent("blockerList\(blockerIndex).json")
            if FileManager.default.fileExists(atPath: sharedPath.path),
               let attachment = NSItemProvider(contentsOf: sharedPath) {
                completeRequest(context: context, attachment: attachment)
                return
            }
        }
        // Fall back to bundled rules
        returnBundledRules(context: context)
    }
    
    private func returnBundledRules(context: NSExtensionContext) {
        guard let bundleURL = Bundle.main.url(forResource: "blockerList", withExtension: "json"),
              let attachment = NSItemProvider(contentsOf: bundleURL) else {
            // If even bundled rules fail, return empty
            returnEmptyRules(context: context)
            return
        }
        completeRequest(context: context, attachment: attachment)
    }
    
    private func returnEmptyRules(context: NSExtensionContext) {
        guard let bundleURL = Bundle.main.url(forResource: "emptyRules", withExtension: "json"),
              let attachment = NSItemProvider(contentsOf: bundleURL) else {
            // Fallback: create empty rules file in temp directory
            let emptyRulesData = "[]".data(using: .utf8)!
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("emptyRules.json")
            try? emptyRulesData.write(to: tempURL)
            if let attachment = NSItemProvider(contentsOf: tempURL) {
                completeRequest(context: context, attachment: attachment)
            }
            return
        }
        completeRequest(context: context, attachment: attachment)
    }
    
    private func completeRequest(context: NSExtensionContext, attachment: NSItemProvider) {
        let item = NSExtensionItem()
        item.attachments = [attachment]
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
}
