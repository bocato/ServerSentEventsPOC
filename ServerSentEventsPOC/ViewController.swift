//
//  ViewController.swift
//  ServerSentEventsPOC
//
//  Created by Eduardo Sanches Bocato on 21/09/18.
//  Copyright © 2018 Bocato. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    // MARK: - IBOutlets
    @IBOutlet private weak var closeButton: UIBarButtonItem!
    @IBOutlet private weak var openButton: UIBarButtonItem!
    @IBOutlet private weak var statusLabel: UILabel!
    @IBOutlet private weak var tableView: UITableView!
    
    // MARK: Properties
    fileprivate var eventSourceConnector: EventSourceConnector?
    fileprivate var events: [String] = []
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        self.closeButton.isEnabled = false
        setupEventSourceConnector()
        updateConnectionStatusLabel()
    }

    // MARK: - Setup
    func updateConnectionStatusLabel() {
        guard let state = eventSourceConnector?.readyState else {
            return
        }
        self.statusLabel.text = state.statusName()
        self.statusLabel.textColor = state.statusColor()
    }
    
    func setupEventSourceConnector() {
        
        let username = "fe8b0af5-1b50-467d-ac0b-b29d2d30136b"
        let password = "ae10ff39ca41dgf0a8"
        
        let basicAuthAuthorization = EventSourceConnector.basicAuth(username, password: password)
        
        let serverURL = "http://127.0.0.1:8080/sse"
        eventSourceConnector = EventSourceConnector(url: serverURL, headers: ["Authorization" : basicAuthAuthorization])
        
        eventSourceConnector?.setOnOpenCallback {
            self.updateConnectionStatusLabel()
            self.openButton.isEnabled = false
            self.closeButton.isEnabled = true
        }
        
        eventSourceConnector?.setOnErrorCallback({ (error) in
            self.statusLabel.text = "Error"
            self.statusLabel.textColor = UIColor.red
            self.eventSourceConnector?.closeConnection()
            self.openButton.isEnabled = true
            self.closeButton.isEnabled = false
        })
        
        eventSourceConnector?.setOnMessageCallback({ (id, event, data) in
            let eventDescription = self.createEventDescription(id: id, event: event, data: data)
            self.events.append(eventDescription)
            self.tableView.reloadData()
        })
        
        eventSourceConnector?.addEventListener("user-connected", handler: { (id, event, data) in
            let eventDescription = self.createEventDescription(id: id, event: event, data: data)
            self.events.append(eventDescription)
            self.tableView.reloadData()
        })
        
    }
    
    // MARK: Helpers
    func createEventDescription(id: String?, event: String?, data: String?) -> String {
        let idString = "ID: \(id ?? "-")"
        let eventString = "\nEVENT: \(event ?? "-")"
        let dataString = "DATA: \(data ?? "-")"
        let eventDescription = idString + "\n" + eventString + "\n" + dataString
        return eventDescription
    }
    
    // MARK: - IBActions
    @IBAction func openButtonDidReceiveTouchUpInside(_ sender: Any) {
        if let state = eventSourceConnector?.readyState, state == .open {
            eventSourceConnector?.closeConnection()
        }
        eventSourceConnector?.openConnection()
        updateConnectionStatusLabel()
    }
    
    @IBAction func closeButtonDidReceiveTouchUpInside(_ sender: Any) {
        eventSourceConnector?.closeConnection()
        updateConnectionStatusLabel()
    }
    
}

extension ViewController: UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return events.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.attributedText = NSAttributedString(string: events[indexPath.row])
        return cell
    }
    
}

extension EventSourceConnector.State {
    
    func statusName() -> String {
        switch self {
        case .closed: return "Closed"
        case .open: return "Open"
        case .connecting: return "Connecting"
        }
    }
    
    func statusColor() ->  UIColor {
        switch self {
        case .closed: return UIColor.red
        case .open: return UIColor.green
        case .connecting: return UIColor.orange        }
    }
    
}

