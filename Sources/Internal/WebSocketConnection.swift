//
//  Copyright © 2019 Gnosis Ltd. All rights reserved.
//

import Foundation
import Starscream

public enum WebSocketConnectionError: Error {
    case connectionError(desc: String, code: UInt16)
}

class WebSocketConnection {

    let url: WCURL
    private let socket: WebSocket
    private let onConnect: (() -> Void)?
    private let onDisconnect: ((Error?) -> Void)?
    private let onTextReceive: ((String) -> Void)?
    // needed to keep connection alive
    private var pingTimer: Timer?
    // TODO: make injectable on server creation
    private let pingInterval: TimeInterval = 30

    private var requestSerializer: RequestSerializer = JSONRPCSerializer()
    private var responseSerializer: ResponseSerializer = JSONRPCSerializer()

    // serial queue for receiving the calls.
    private let serialCallbackQueue: DispatchQueue
    private var websocketConnected: Bool = false

    var isOpen: Bool {
        return websocketConnected
    }

    init(url: WCURL,
         onConnect: (() -> Void)?,
         onDisconnect: ((Error?) -> Void)?,
         onTextReceive: ((String) -> Void)?) {
        self.url = url
        self.onConnect = onConnect
        self.onDisconnect = onDisconnect
        self.onTextReceive = onTextReceive
        serialCallbackQueue = DispatchQueue(label: "org.walletconnect.swift.connection-\(url.bridgeURL)-\(url.topic)")
        var request = URLRequest(url: url.bridgeURL)
        request.timeoutInterval = 30
        
        socket = WebSocket(request: request)
        socket.delegate = self
        socket.callbackQueue = serialCallbackQueue
    }

    func open() {
        socket.connect()
    }

    func close() {
        socket.disconnect()
    }

    func send(_ text: String) {
        guard websocketConnected else { return }
        socket.write(string: text)
        log(text)
    }

    private func log(_ text: String) {
        if let request = try? requestSerializer.deserialize(text, url: url).json().string {
            print("WC: ==> \(request)")
        } else if let response = try? responseSerializer.deserialize(text, url: url).json().string {
            print("WC: ==> \(response)")
        } else {
            print("WC: ==> \(text)")
        }
    }

}

extension WebSocketConnection: WebSocketDelegate {
    
    func didReceive(event: WebSocketEvent, client: WebSocket) {
        switch event {
        case .connected:
            websocketConnected = true
            pingTimer = Timer.scheduledTimer(withTimeInterval: pingInterval, repeats: true) { [weak self] _ in
                print("WC: ==> ping")
                self?.socket.write(ping: Data())
            }
            onConnect?()
            
        case .disconnected(let resason, let code):
            websocketConnected = false
            let error = WebSocketConnectionError.connectionError(desc: resason, code: code)
            pingTimer?.invalidate()
            onDisconnect?(error)
        case .text(let text):
            onTextReceive?(text)
        default:
            break
        }
    }

    /*
    func websocketDidConnect(socket: WebSocketClient) {
        pingTimer = Timer.scheduledTimer(withTimeInterval: pingInterval, repeats: true) { [weak self] _ in
            print("WC: ==> ping")
            self?.socket.write(ping: Data())
        }
        onConnect?()
    }

    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        pingTimer?.invalidate()
        onDisconnect?(error)
    }

    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        onTextReceive?(text)
    }

    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        // no-op
    }
    */

}
