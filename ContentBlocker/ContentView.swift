//
//  ContentView.swift
//  ContentBlocker
//
//  Created by ian on 16.03.2026.
//

import SwiftUI
import SafariServices
import Combine

struct ContentView: View {
    @StateObject private var viewModel = ContentBlockerViewModel()
    
    var body: some View {
        NavigationView {
            List {
                // Extensions Toggle Section
                Section {
                    Toggle("Content Blockers", isOn: $viewModel.isBlockersEnabled)
                        .onChange(of: viewModel.isBlockersEnabled) { _, newValue in
                            viewModel.toggleAllBlockers(enabled: newValue)
                        }
                } header: {
                    Text("Extensions")
                } footer: {
                    Text("Enable or disable all content blocker extensions. You also need to enable them in Settings > Safari > Extensions.")
                }
                
                // Update Section
                Section {
                    Button(action: {
                        viewModel.checkForUpdates()
                    }) {
                        HStack {
                            Text("Check for Updates")
                            Spacer()
                            if viewModel.isCheckingUpdates {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            }
                        }
                    }
                    .disabled(viewModel.isCheckingUpdates)
                } header: {
                    Text("Updates")
                } footer: {
                    if let message = viewModel.updateStatusMessage {
                        Text(message)
                    }
                }
                
                // Versions Section
                Section {
                    ForEach(1...5, id: \.self) { index in
                        HStack {
                            Text("ContentBlocker\(index)")
                            Spacer()
                            Text("v\(viewModel.getVersion(for: index))")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Rule Versions")
                }
                
                // Last Update Section
                Section {
                    HStack {
                        Text("Last Updated")
                        Spacer()
                        Text(viewModel.lastUpdateDateString)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Information")
                }
            }
            .navigationTitle("Content Blocker")
            .alert("Update", isPresented: $viewModel.showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.alertMessage)
            }
        }
    }
}

// MARK: - ViewModel

class ContentBlockerViewModel: ObservableObject {
    @Published var isBlockersEnabled: Bool {
        didSet {
            sharedDefaults?.set(isBlockersEnabled, forKey: "blockersEnabled")
            sharedDefaults?.synchronize()
        }
    }
    @Published var isCheckingUpdates = false
    @Published var updateStatusMessage: String?
    @Published var showAlert = false
    @Published var alertMessage = ""
    
    private let appGroupIdentifier = "group.com.ian.ContentBlocker"
    private var sharedDefaults: UserDefaults?
    
    private let blockerIdentifiers = [
        "com.ian.ContentBlocker.ContentBlocker1",
        "com.ian.ContentBlocker.ContentBlocker2",
        "com.ian.ContentBlocker.ContentBlocker3",
        "com.ian.ContentBlocker.ContentBlocker4",
        "com.ian.ContentBlocker.ContentBlocker5"
    ]
    
    private let apiURL = "https://api.cat.dp.ua/ContentBlocker/blockerList.json"
    
    init() {
        self.sharedDefaults = UserDefaults(suiteName: appGroupIdentifier)
        // Default to disabled (false)
        self.isBlockersEnabled = sharedDefaults?.object(forKey: "blockersEnabled") as? Bool ?? false
    }
    
    var lastUpdateDateString: String {
        if let date = sharedDefaults?.object(forKey: "lastUpdateDate") as? Date {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return "Never"
    }
    
    func getVersion(for index: Int) -> Int {
        return sharedDefaults?.integer(forKey: "blockerVersion\(index)") ?? 0
    }
    
    private func setVersion(_ version: Int, for index: Int) {
        sharedDefaults?.set(version, forKey: "blockerVersion\(index)")
        sharedDefaults?.synchronize()
    }
    
    func toggleAllBlockers(enabled: Bool) {
        // Update shared defaults first
        sharedDefaults?.set(enabled, forKey: "blockersEnabled")
        sharedDefaults?.synchronize()
        
        // Then reload all content blockers to apply changes
        for identifier in blockerIdentifiers {
            SFContentBlockerManager.reloadContentBlocker(withIdentifier: identifier) { error in
                if let error = error {
                    print("Error reloading \(identifier): \(error.localizedDescription)")
                }
            }
        }
    }
    
    func checkForUpdates() {
        isCheckingUpdates = true
        updateStatusMessage = "Checking for updates..."
        
        guard let url = URL(string: apiURL) else {
            handleError("Invalid API URL")
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    self.handleError("Network error: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    self.handleError("No data received")
                    return
                }
                
                do {
                    let blockerList = try JSONDecoder().decode([BlockerInfo].self, from: data)
                    self.processBlockerList(blockerList)
                } catch {
                    self.handleError("Failed to parse response: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
    
    private func processBlockerList(_ blockerList: [BlockerInfo]) {
        var updatesNeeded: [(index: Int, info: BlockerInfo)] = []
        
        for (index, info) in blockerList.enumerated() {
            let blockerIndex = index + 1
            let currentVersion = getVersion(for: blockerIndex)
            
            if info.version != currentVersion {
                updatesNeeded.append((blockerIndex, info))
            }
        }
        
        if updatesNeeded.isEmpty {
            isCheckingUpdates = false
            updateStatusMessage = "All rules are up to date"
            alertMessage = "All blocking rules are up to date!"
            showAlert = true
            return
        }
        
        updateStatusMessage = "Downloading \(updatesNeeded.count) update(s)..."
        downloadUpdates(updatesNeeded)
    }
    
    private func downloadUpdates(_ updates: [(index: Int, info: BlockerInfo)]) {
        let group = DispatchGroup()
        var successCount = 0
        var failedCount = 0
        
        for update in updates {
            group.enter()
            
            guard let url = URL(string: update.info.url) else {
                failedCount += 1
                group.leave()
                continue
            }
            
            URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
                defer { group.leave() }
                
                guard let self = self, let data = data, error == nil else {
                    DispatchQueue.main.async {
                        failedCount += 1
                    }
                    return
                }
                
                // Save the downloaded rules to the app's shared container
                if self.saveBlockerRules(data, for: update.index) {
                    DispatchQueue.main.async {
                        self.setVersion(update.info.version, for: update.index)
                        successCount += 1
                    }
                    
                    // Reload the content blocker
                    let identifier = self.blockerIdentifiers[update.index - 1]
                    SFContentBlockerManager.reloadContentBlocker(withIdentifier: identifier) { _ in }
                } else {
                    DispatchQueue.main.async {
                        failedCount += 1
                    }
                }
            }.resume()
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            
            self.isCheckingUpdates = false
            self.sharedDefaults?.set(Date(), forKey: "lastUpdateDate")
            self.sharedDefaults?.synchronize()
            
            if failedCount == 0 {
                self.updateStatusMessage = "Successfully updated \(successCount) rule(s)"
                self.alertMessage = "Successfully updated \(successCount) blocking rule(s)!"
            } else {
                self.updateStatusMessage = "Updated \(successCount), failed \(failedCount)"
                self.alertMessage = "Updated \(successCount) rule(s), but \(failedCount) failed."
            }
            self.showAlert = true
        }
    }
    
    private func saveBlockerRules(_ data: Data, for index: Int) -> Bool {
        guard let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            print("Failed to get shared container")
            return false
        }
        
        let filePath = sharedContainer.appendingPathComponent("blockerList\(index).json")
        do {
            try data.write(to: filePath)
            return true
        } catch {
            print("Failed to save blocker rules: \(error)")
            return false
        }
    }
    
    private func handleError(_ message: String) {
        isCheckingUpdates = false
        updateStatusMessage = message
        alertMessage = message
        showAlert = true
    }
}

// MARK: - Models

struct BlockerInfo: Codable {
    let version: Int
    let url: String
}

#Preview {
    ContentView()
}
