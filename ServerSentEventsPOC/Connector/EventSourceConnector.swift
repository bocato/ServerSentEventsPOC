//
//  EventSourceConnector.swift
//  ServerSentEventsPOC
//
//  Created by Eduardo Sanches Bocato on 24/09/18.
//  Copyright © 2018 Bocato. All rights reserved.
//

import Foundation

open class EventSourceConnector: NSObject, URLSessionDataDelegate {
    
    // MARK: - Enums
    public enum State {
        case connecting
        case open
        case closed
    }
    
    // MARK: - Constants
    static let DefaultsKey = "com.bocato.eventSourceConnector.lastEventId"
    fileprivate let validNewlineCharacters = ["\r\n", "\n", "\r"]
    
    // MARK: - Aliases
    public typealias OnOpenCallbackClosure = (() -> Void)
    public typealias OnErrorCallbackClosure = ((NSError?) -> Void)
    public typealias OnMessageCallbackClosure = ((_ id: String?, _ event: String?, _ data: String?) -> Void)
    public typealias OnEventReceivedCallbackClosure = (_ id: String?, _ event: String?, _ data: String?) -> Void
    
    // MARK: - Properties
    let url: URL
    fileprivate let lastEventIDKey: String
    fileprivate let receivedString: NSString?
    fileprivate var onOpenCallback: OnOpenCallbackClosure?
    fileprivate var onErrorCallback: OnErrorCallbackClosure?
    fileprivate var onMessageCallback: OnMessageCallbackClosure?
    fileprivate var eventListeners = Dictionary<String, OnEventReceivedCallbackClosure>()
    fileprivate var headers: Dictionary<String, String>
    fileprivate var operationQueue: OperationQueue
    fileprivate var errorBeforeSetErrorCallBack: NSError?
    fileprivate let uniqueIdentifier: String

    open internal(set) var readyState: State
    open fileprivate(set) var retryTime = 3000
    
    internal var urlSession: Foundation.URLSession?
    internal var task: URLSessionDataTask?
    internal let receivedDataBuffer: NSMutableData
    
    var event = Dictionary<String, String>()
    
    // MARK: - Initialization
    public init(url: String, headers: [String : String] = [:]) {
        self.url = URL(string: url)!
        self.headers = headers
        self.readyState = .closed
        self.operationQueue = OperationQueue()
        self.receivedString = nil
        self.receivedDataBuffer = NSMutableData()
        
        let port = String(self.url.port ?? 80)
        let relativePath = self.url.relativePath
        let host = self.url.host ?? ""
        let scheme = self.url.scheme ?? ""
        
        self.uniqueIdentifier = "\(scheme).\(host).\(port).\(relativePath)"
        self.lastEventIDKey = "\(EventSourceConnector.DefaultsKey).\(self.uniqueIdentifier)"
        
        super.init()
//        self.openConnection()
    }

    // helpers -=== refactpr
    fileprivate func receivedMessageToClose(_ httpResponse: HTTPURLResponse?) -> Bool {
        guard let response = httpResponse else {
            return false
        }
        
        if response.statusCode == 204 {
            self.closeConnection()
            return true
        }
        return false
    }
    
}

// MARK: - Callbacks Configuration
extension EventSourceConnector {
    
    open func setOnOpenCallback(_ callback: @escaping (OnOpenCallbackClosure)) {
        self.onOpenCallback = callback
    }
    
    open func setOnErrorCallback(_ callback: @escaping (OnErrorCallbackClosure)) {
        self.onErrorCallback = callback
        
        if let errorBeforeSet = self.errorBeforeSetErrorCallBack {
            self.onErrorCallback!(errorBeforeSet)
            self.errorBeforeSetErrorCallBack = nil
        }
    }
    
    open func setOnMessageCallback(_ callback: @escaping (OnMessageCallbackClosure)) {
        self.onMessageCallback = callback
    }
    
    open func addEventListener(_ event: String, handler: @escaping (OnEventReceivedCallbackClosure)) {
        self.eventListeners[event] = handler
    }
    
    open func removeEventListener(_ event: String) -> Void {
        self.eventListeners.removeValue(forKey: event)
    }
    
    open func events() -> Array<String> {
        return Array(self.eventListeners.keys)
    }
}

// MARK: - Connection
extension EventSourceConnector {
    
    func openConnection(customConfiguration: URLSessionConfiguration? = nil) {
        
        var httpAdditionalHeaders = createDefaultHeaders(for: lastEventIDKey)
        headers.forEach { (key, value) in
            httpAdditionalHeaders[key] = value
        }
        
        let configuration = customConfiguration ?? createDefaultURLSessionConfiguration(with: httpAdditionalHeaders)
        
        readyState = .connecting
        urlSession = createNewSession(with: configuration)
        self.task = urlSession!.dataTask(with: url)
        
        resumeSession()
        
    }
    
    open func closeConnection() {
        self.readyState = .closed
        self.urlSession?.invalidateAndCancel()
    }
    
    internal func resumeSession() {
        self.task!.resume()
    }
    
    private func createDefaultHeaders(for lastEventId: String? = nil) -> [String: String] {
        
        var defaultHeaders = [String: String]()
        
        if let eventID = lastEventId {
            defaultHeaders["Last-Event-Id"] = eventID
        }
        
        defaultHeaders["Accept"] = "text/event-stream"
        defaultHeaders["Cache-Control"] = "no-cache"
        
        return defaultHeaders
    }
    
    private  func createDefaultURLSessionConfiguration(with httpAdditionalHeaders: [String: String]) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = TimeInterval(INT_MAX)
        configuration.timeoutIntervalForResource = TimeInterval(INT_MAX)
        configuration.httpAdditionalHeaders = httpAdditionalHeaders
        return configuration
    }
    
    internal func createNewSession(with configuration: URLSessionConfiguration) -> URLSession {
        return URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: operationQueue
        )
    }
    
}

// MARK: - Event Parsers
extension EventSourceConnector {
    
    fileprivate func extractEventsFromBuffer() -> [String] {
        var events = [String]()
        
        // Find first occurrence of delimiter
        var searchRange =  NSRange(location: 0, length: receivedDataBuffer.length)
        while let foundRange = searchForEventInRange(searchRange) {
            // Append event
            if foundRange.location > searchRange.location {
                let dataChunk = receivedDataBuffer.subdata(
                    with: NSRange(location: searchRange.location, length: foundRange.location - searchRange.location)
                )
                
                if let text = String(bytes: dataChunk, encoding: .utf8) {
                    events.append(text)
                }
            }
            // Search for next occurrence of delimiter
            searchRange.location = foundRange.location + foundRange.length
            searchRange.length = receivedDataBuffer.length - searchRange.location
        }
        
        // Remove the found events from the buffer
        self.receivedDataBuffer.replaceBytes(in: NSRange(location: 0, length: searchRange.location), withBytes: nil, length: 0)
        
        return events
    }
    
    fileprivate func searchForEventInRange(_ searchRange: NSRange) -> NSRange? {
        let delimiters = validNewlineCharacters.map { "\($0)\($0)".data(using: String.Encoding.utf8)! }
        
        for delimiter in delimiters {
            let foundRange = receivedDataBuffer.range(of: delimiter,
                                                      options: NSData.SearchOptions(),
                                                      in: searchRange)
            if foundRange.location != NSNotFound {
                return foundRange
            }
        }
        
        return nil
    }
    
    fileprivate func parseEventStream(_ events: [String]) {
        var parsedEvents: [(id: String?, event: String?, data: String?)] = Array()
        
        for event in events {
            if event.isEmpty {
                continue
            }
            
            if event.hasPrefix(":") {
                continue
            }
            
            if (event as NSString).contains("retry:") {
                if let reconnectTime = parseRetryTime(event) {
                    self.retryTime = reconnectTime
                }
                continue
            }
            
            parsedEvents.append(parseEvent(event))
        }
        
        for parsedEvent in parsedEvents {
            self.lastEventID = parsedEvent.id
            
            if parsedEvent.event == nil {
                if let data = parsedEvent.data, let onMessage = self.onMessageCallback {
                    DispatchQueue.main.async {
                        onMessage(self.lastEventID, "message", data)
                    }
                }
            }
            
            if let event = parsedEvent.event, let data = parsedEvent.data, let eventHandler = self.eventListeners[event] {
                DispatchQueue.main.async {
                    eventHandler(self.lastEventID, event, data)
                }
            }
        }
    }
    
    internal var lastEventID: String? {
        set {
            if let lastEventID = newValue {
                let defaults = UserDefaults.standard
                defaults.set(lastEventID, forKey: lastEventIDKey)
                defaults.synchronize()
            }
        }
        
        get {
            let defaults = UserDefaults.standard
            
            if let lastEventID = defaults.string(forKey: lastEventIDKey) {
                return lastEventID
            }
            return nil
        }
    }
    
    fileprivate func parseEvent(_ eventString: String) -> (id: String?, event: String?, data: String?) {
        var event = Dictionary<String, String>()
        
        for line in eventString.components(separatedBy: CharacterSet.newlines) as [String] {
            autoreleasepool {
                let (k, value) = self.parseKeyValuePair(line)
                guard let key = k else { return }
                
                if let value = value {
                    if event[key] != nil {
                        event[key] = "\(event[key]!)\n\(value)"
                    } else {
                        event[key] = value
                    }
                } else if value == nil {
                    event[key] = ""
                }
            }
        }
        
        return (event["id"], event["event"], event["data"])
    }
    
    fileprivate func parseKeyValuePair(_ line: String) -> (String?, String?) {
        var key: NSString?, value: NSString?
        let scanner = Scanner(string: line)
        scanner.scanUpTo(":", into: &key)
        scanner.scanString(":", into: nil)
        
        for newline in validNewlineCharacters {
            if scanner.scanUpTo(newline, into: &value) {
                break
            }
        }
        
        return (key as String?, value as String?)
    }
    
    fileprivate func parseRetryTime(_ eventString: String) -> Int? {
        var reconnectTime: Int?
        let separators = CharacterSet(charactersIn: ":")
        if let milli = eventString.components(separatedBy: separators).last {
            let milliseconds = trim(milli)
            
            if let intMiliseconds = Int(milliseconds) {
                reconnectTime = intMiliseconds
            }
        }
        return reconnectTime
    }
    
    fileprivate func trim(_ string: String) -> String {
        return string.trimmingCharacters(in: CharacterSet.whitespaces)
    }
    
    fileprivate func hasHttpError(code: Int) -> Bool {
        return code >= 400
    }
    
    class open func basicAuth(_ username: String, password: String) -> String {
        let authString = "\(username):\(password)"
        let authData = authString.data(using: String.Encoding.utf8)
        let base64String = authData!.base64EncodedString(options: [])
        
        return "Basic \(base64String)"
    }
    
}

// MARK: - URLSessionDataDelegate
extension EventSourceConnector: URLSessionDelegate {
    
    open func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if self.receivedMessageToClose(dataTask.response as? HTTPURLResponse) {
            return
        }
        
        if self.readyState != .open {
            return
        }
        
        self.receivedDataBuffer.append(data)
        let eventStream = extractEventsFromBuffer()
        self.parseEventStream(eventStream)
    }
    
    open func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        completionHandler(URLSession.ResponseDisposition.allow)
        
        if self.receivedMessageToClose(dataTask.response as? HTTPURLResponse) {
            return
        }
        
        self.readyState = .open
        if self.onOpenCallback != nil {
            DispatchQueue.main.async {
                self.onOpenCallback!()
            }
        }
    }
    
    open func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        self.readyState = .closed
        
        if self.receivedMessageToClose(task.response as? HTTPURLResponse) {
            return
        }
        
        guard let urlResponse = task.response as? HTTPURLResponse else {
            return
        }
        
        if !hasHttpError(code: urlResponse.statusCode) && (error == nil || (error! as NSError).code != -999) {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(retryTime)) {
                self.openConnection()
            }
        }
        
        DispatchQueue.main.async {
            var theError: NSError? = error as NSError?
            
            if self.hasHttpError(code: urlResponse.statusCode) {
                theError = NSError(
                    domain: "com.bocato.eventSourceConnector.error",
                    code: -1,
                    userInfo: ["message": "HTTP Status Code: \(urlResponse.statusCode)"]
                )
                self.closeConnection()
            }
            
            if let errorCallback = self.onErrorCallback {
                errorCallback(theError)
            } else {
                self.errorBeforeSetErrorCallBack = theError
            }
        }
    }
    
}
