//
//  DNS_Easy_SwitcherApp.swift
//  DNS Easy Switcher
//
//  Created by Gregory LINFORD on 23/02/2025.
//

import SwiftUI
import SwiftData
import AppKit

@main
struct DNS_Easy_SwitcherApp: App {
    @StateObject private var menuBarController = MenuBarController()
    
    let modelContainer: ModelContainer?
    let storageError: Error?
    @State private var hasPresentedStorageError = false
    
    init() {
        do {
            self.modelContainer = try DNSPersistence.makeContainer()
            self.storageError = nil
        } catch {
            self.modelContainer = nil
            self.storageError = error
        }
    }

    var body: some Scene {
        WindowGroup(id: "hidden") {
            Color.clear
                .frame(width: 0, height: 0)
                .hidden()
                .onAppear {
                    if storageError != nil && !hasPresentedStorageError {
                        hasPresentedStorageError = true
                        showStorageError()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 0, height: 0)
        
        MenuBarExtra("DNS Switcher", systemImage: modelContainer == nil ? "exclamationmark.triangle" : "network") {
            if let modelContainer {
                MenuBarView()
                    .modelContainer(modelContainer)
                    .frame(width: 300)
            } else {
                Text("Saved DNS profiles could not be loaded.")
                Button("Show Storage Error…", action: showStorageError)
                Divider()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    private func showStorageError() {
        guard let storageError else { return }
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Could Not Load Saved DNS Profiles"
            alert.informativeText = "\(storageError.localizedDescription)\n\nPlease resolve the storage error and relaunch DNS Easy Switcher. Profile editing is unavailable until your saved data can be loaded."
            alert.addButton(withTitle: "OK")
            NSApplication.shared.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}
