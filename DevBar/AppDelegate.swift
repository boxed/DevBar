//
//  AppDelegate.swift
//  DevBar
//
//  Created by Anders Hovmöller on 2018-10-17.
//  Copyright © 2018 Anders Hovmöller. All rights reserved.
//

import Cocoa
import IOKit.ps

struct Display : Decodable {
    let symbol : String
    let title : String
}

struct Metadata : Decodable {
    let display: [String: Display]
}

struct Result : Decodable {
    let metadata: Metadata
    let data: [String: [PR]]
}

struct PR : Decodable {
    let title: String
    let url: String
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var preferencesWindow: NSWindow!
    
    var statusBarItem : NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var timer : Timer? = nil
    var menu: NSMenu = NSMenu()
    var menuOpen = false
    var hasShownPreferences = false
    var requestInFlight = false
    var lastFetchTime: Date = .distantPast
    let batteryPollingInterval: TimeInterval = 30

    func isOnBatteryPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any],
              !sources.isEmpty else {
            return false  // Desktop Mac or unable to determine — assume AC
        }
        for source in sources {
            if let info = IOPSGetPowerSourceDescription(snapshot, source as CFTypeRef)?.takeUnretainedValue() as? [String: Any],
               let powerSource = info[kIOPSPowerSourceStateKey] as? String {
                if powerSource == kIOPSBatteryPowerValue {
                    return true
                }
            }
        }
        return false
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        statusBarItem.button?.title = ""
        statusBarItem.menu = menu
        menu.delegate = self
        self.update()
        
        UserDefaults.standard.register(defaults: ["refresh_seconds": 1.0])

        var refresh_seconds = UserDefaults.standard.float(forKey: "refresh_seconds")
        if refresh_seconds <= 0 {
            refresh_seconds = 1
        }
        timer = Timer.scheduledTimer(timeInterval: TimeInterval(refresh_seconds), target: self, selector: #selector(self.update), userInfo: nil, repeats: true)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true
    }
    
    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
    }
    
    func createMenuItems(_ prs: [PR], title: String) {
        guard !prs.isEmpty else { return }
        
        menu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
        for pr in prs {
            let menuItem = NSMenuItem(title: "\(pr.title)", action: #selector(open), keyEquivalent: "")
            menuItem.representedObject = pr as AnyObject
            menu.addItem(menuItem)
        }
    }
   
    func buildTitle(list: [PR], emoji: String) -> String{
        if !list.isEmpty {
            return #"  \#(emoji) \#(list.count > 1 ? String(list.count) : "")"#
        }
        return ""
    }
    
    @objc
    func open(sender: NSMenuItem) {
        guard let pr = sender.representedObject as? PR,
              let url = URL(string: pr.url) else { return }
        NSWorkspace.shared.open(url)
    }
    
    @objc
    func quit() {
        NSApplication.shared.terminate(self)
    }

    
    @objc
    func preferences() {
        self.preferencesWindow!.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func updateMenu(result: Result?) {
        if menuOpen {
            return
        }

        self.menu.removeAllItems()

        var title = ""
        if let result = result {
            for (k, v) in result.data.sorted(by: {$0.key < $1.key } ) {
                let display = result.metadata.display[k, default: Display(symbol: "", title: k)]
                title += self.buildTitle(list: v, emoji: display.symbol)
                self.createMenuItems(v, title: display.title)
            }
            
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if title == "" {
                title = "✓"
            }
        }
        else {
            title = "!"
        }
        self.statusBarItem.button?.title = title
        self.menu.addItem(NSMenuItem.separator())
        self.menu.addItem(NSMenuItem.init(title: "Preferences", action: #selector(self.preferences), keyEquivalent: ""))
        self.menu.addItem(NSMenuItem.init(title: "Refresh", action: #selector(self.update), keyEquivalent: ""))
        self.menu.addItem(NSMenuItem.init(title: "Quit", action: #selector(self.quit), keyEquivalent: ""))
    }
    
    @objc
    func update() {
        if menuOpen {
            return
        }
        if requestInFlight {
            return
        }
        if isOnBatteryPower() && Date().timeIntervalSince(lastFetchTime) < batteryPollingInterval {
            return
        }
        lastFetchTime = Date()
        requestInFlight = true
        DispatchQueue.global(qos: .background).async {
            if let base_url = UserDefaults.standard.string(forKey: "url") {
                guard let url = URL(string: base_url + "?username=\(NSUserName())") else {
                    DispatchQueue.main.async {
                        self.requestInFlight = false
                        self.updateMenu(result: nil)
                    }
                    return
                }
                let request = URLRequest(url: url)
                let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
                    defer {
                        DispatchQueue.main.async { self.requestInFlight = false }
                    }
                    if let response = response as? HTTPURLResponse {

                        if response.statusCode == 503 {
                            return
                        }

                       if error != nil {
                            DispatchQueue.main.async {
                                self.updateMenu(result: nil)
                            }
                            return
                        }

                        do {
                            if let data = data {
                                let result = try JSONDecoder().decode(Result.self, from: data)
                                DispatchQueue.main.async {
                                    self.updateMenu(result: result)
                                }
                            }
                        }
                        catch {
                            DispatchQueue.main.async {
                                self.updateMenu(result: nil)
                            }
                        }
                    }
                }
                task.resume()
            }
            else {
                DispatchQueue.main.async {
                    self.requestInFlight = false
                    if !self.hasShownPreferences {
                        self.preferences()
                        self.updateMenu(result: nil)
                        self.hasShownPreferences = true
                    }
                }
            }
        }
    }
}

