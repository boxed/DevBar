//
//  AppDelegate.swift
//  DevBar
//
//  Created by Anders Hovmöller on 2018-10-17.
//  Copyright © 2018 Anders Hovmöller. All rights reserved.
//

import Cocoa

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

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        statusBarItem.button?.title = ""
        statusBarItem.menu = menu
        menu.delegate = self
        self.update()

        // update every second
        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(self.update), userInfo: nil, repeats: true)
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
            return "  \(emoji) \(list.count)"
        }
        return ""
    }
    
    @objc
    func open(sender: NSMenuItem) {
        let pr = sender.representedObject as! PR
        NSWorkspace.shared.open(URL(string: pr.url)!)
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
        DispatchQueue.global(qos: .background).async {
            if var base_url = UserDefaults.standard.string(forKey: "url") {
                // You need to create the file url.swift that looks like: let base_url = "https://some.server/"
                if !base_url.hasSuffix("/") {
                    base_url += "/"
                }
                guard let url = URL(string: base_url + "\(NSUserName())") else {
                    DispatchQueue.main.async {
                        self.updateMenu(result: nil)
                    }
                    return
                }
                
                do {
                    let webString = try String(contentsOf: url)
                    guard let json_data : Data = webString.data(using: .utf8) else { return }
                    
                    let result = try JSONDecoder().decode(Result.self, from: json_data)
                    
                    DispatchQueue.main.async {
                        self.updateMenu(result: result)
                    }
                    
                }
                catch {
                    DispatchQueue.main.async {
                        self.updateMenu(result: nil)
                    }
                }
            }
            else {
                DispatchQueue.main.async {
                    self.preferences()
                    self.updateMenu(result: nil)
                }
            }
        }
    }
}

