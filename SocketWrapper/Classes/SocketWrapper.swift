//
//  ClientSocketWrapper.swift
//  SocketWrapper
//
//  Created by Rahul Behera on 12/30/22.
//

import Foundation
import Network

@objc
public class ClientSocketWrapper: SocketWrapper {
  let host: Network.NWEndpoint.Host
  let port: Network.NWEndpoint.Port

  @objc public init(
    host: String, port: UInt16, timeoutSeconds: Int, tls: Bool
  ) {
    self.host = NWEndpoint.Host(host)
    self.port = NWEndpoint.Port(rawValue: port)!
    let nwConnection: NWConnection
    if tls {
      let options = NWProtocolTCP.Options()
      options.connectionTimeout = timeoutSeconds
      let tlsOptions = NWProtocolTLS.Options()

      sec_protocol_options_set_peer_authentication_required(
        tlsOptions.securityProtocolOptions, false)

      let params = NWParameters(tls: tlsOptions, tcp: options)
      nwConnection = NWConnection(host: self.host, port: self.port, using: params)
    } else {
      let options = NWProtocolTCP.Options()
      options.connectionTimeout = timeoutSeconds
      let params = NWParameters(tls: nil, tcp: options)
      nwConnection = NWConnection(host: self.host, port: self.port, using: params)
    }
    super.init(connection: nwConnection)

  }

  @objc public func setStateUpdateHandler(
    handler: @escaping (ClientSocketWrapper, String, String?, Bool, Bool, Bool) -> Void
  ) {
    connection.stateUpdateHandler = { state in
      switch state {
      case .ready:
        handler(self, "\(state)", nil, false, false, false)
      case .failed(let error):
        self.notifyError(socketWrapper: self, state: state, error: error, handler: handler)
      case .waiting(let error):
        self.notifyError(socketWrapper: self, state: state, error: error, handler: handler)
      case .setup:
        handler(self, "\(state)", nil, false, false, false)
      case .preparing:
        handler(self, "\(state)", nil, false, false, false)
      case .cancelled:
        handler(self, "\(state)", nil, false, false, false)
      @unknown default:
        fatalError("Unknown NWError state \(state)")
      }
    }
  }

  @objc public func start() {
    connection.start(queue: DispatchQueue.global())
  }

  @objc public func currentState() -> String {
    return "\(self.connection.state)"
  }

  func notifyError(
    socketWrapper: ClientSocketWrapper, state: NWConnection.State, error: NWError,
    handler: @escaping (ClientSocketWrapper, String, String?, Bool, Bool, Bool) -> Void
  ) {
    switch error {
    case .posix(_):
      handler(self, "\(state)", error.debugDescription, true, false, false)
    case .dns(_):
      handler(self, "\(state)", error.debugDescription, false, true, false)
    case .tls(_):
      handler(self, "\(state)", error.debugDescription, false, false, true)
    @unknown default:
      fatalError("Unknown NWError case \(error)")
    }
  }
}

@objc
public class ServerSocketWrapper: SocketWrapper {

  public init(
    connection: NWConnection,
    completion: @escaping (ServerSocketWrapper, String?, Bool, Bool, Bool) -> Void
  ) {
    super.init(connection: connection)
    connection.stateUpdateHandler = { state in
      switch state {
      case .ready:
        completion(self, nil, false, false, false)
      case .failed(let error):
        self.notifyCompletion(socketWrapper: self, error: error, completion: completion)
      case .waiting(let error):
        self.notifyCompletion(socketWrapper: self, error: error, completion: completion)
      default:
        ()
      }
    }
    connection.start(queue: DispatchQueue.global())

  }
  func notifyCompletion(
    socketWrapper: ServerSocketWrapper, error: NWError,
    completion: @escaping (ServerSocketWrapper, String?, Bool, Bool, Bool) -> Void
  ) {
    switch error {
    case .posix(_):
      completion(self, error.debugDescription, true, false, false)
    case .dns(_):
      completion(self, error.debugDescription, false, true, false)
    case .tls(_):
      completion(self, error.debugDescription, false, false, true)
    @unknown default:
      fatalError("Unknown NWError case \(error)")
    }
    cancel()
  }
}

@objc
public class ServerSocketListenerWrapper: NSObject {

  let listener: NWListener
  private var cb: ((NWConnection) -> Void)? = nil
  private var closeCb: [(() -> Void)] = []

  @objc public init(port: Int, host: String?, backlog: Int) {
    let nwEndpointPort: NWEndpoint.Port
    if port < 0 {
      nwEndpointPort = .any
    } else {
      nwEndpointPort = NWEndpoint.Port(rawValue: UInt16(port))!
    }
    let listener = try! NWListener(using: .tcp, on: nwEndpointPort)
    if backlog < 1 {
      listener.newConnectionLimit = NWListener.InfiniteConnectionLimit
    } else {
      listener.newConnectionLimit = Int(backlog)
    }
    self.listener = listener
    super.init()
    listener.newConnectionHandler = { connection in
      guard let cb = self.cb else { return }
      cb(connection)
    }
  }

  @objc public func assignCloseCallback(cb: @escaping () -> Void) {
    self.closeCb.append(cb)
  }

  @objc public func assignAcceptedCallbackListener(
    acceptedClient: @escaping (ServerSocketWrapper) -> Void
  ) {
    self.cb = { connection in
      let _ = ServerSocketWrapper(connection: connection) {
        (serverSocketWrapper, errorString, isPosixError, isDnsError, isTlsError) in
        if errorString == nil && !isPosixError && !isDnsError && !isTlsError {
          acceptedClient(serverSocketWrapper)
        }
      }
    }
  }

  @objc public func start(
    completionHandler: @escaping (ServerSocketListenerWrapper, String?, Bool, Bool, Bool) -> Void
  ) {
    listener.stateUpdateHandler = { state in
      switch state {
      case .setup:
        ()
      case .waiting(let error):
        self.notifyCompletion(error: error, completionHandler: completionHandler)
      case .ready:
        completionHandler(self, nil, false, false, false)
      case .failed(let error):
        self.notifyCompletion(error: error, completionHandler: completionHandler)
      case .cancelled:
        self.cb = nil
        for closeCallback in self.closeCb {
          closeCallback()
        }
        self.closeCb = []
      @unknown default:
        ()
      }
    }
    listener.start(queue: .global())

  }

  @objc public func isOpen() -> Bool {
    return listener.state == .ready
  }

  @objc public func port() -> Int {
    if !isOpen() {
      return -1
    }
    guard let listenerPort = listener.port else {
      return -1
    }
    return Int(listenerPort.rawValue)
  }

  @objc public func stopListeningForInboundConnections(cb: @escaping () -> Void) {
    if listener.state == .cancelled {
      cb()
    } else {
      listener.cancel()
      self.closeCb.append(cb)
    }
  }

  func notifyCompletion(
    error: NWError,
    completionHandler: @escaping (ServerSocketListenerWrapper, String?, Bool, Bool, Bool) -> Void
  ) {
    switch error {
    case .posix(_):
      completionHandler(self, error.debugDescription, true, false, false)
    case .dns(_):
      completionHandler(self, error.debugDescription, false, true, false)
    case .tls(_):
      completionHandler(self, error.debugDescription, false, false, true)
    @unknown default:
      fatalError("Unknown NWError case \(error)")
    }
  }

}

@objc
public class SocketWrapper: NSObject {
  let connection: NWConnection

  public init(connection: NWConnection) {
    self.connection = connection
  }

  @objc public func isOpen() -> Bool {
    return connection.state == NWConnection.State.ready
  }

  @objc public func localPort() -> Int {
    switch connection.currentPath?.localEndpoint as? NWEndpoint {
    case .hostPort(_, let port):
      return Int(port.rawValue)
    default:
      return -1
    }
  }
  @objc public func remotePort() -> Int {
    switch connection.currentPath?.remoteEndpoint as? NWEndpoint {
    case .hostPort(_, let port):
      return Int(port.rawValue)
    default:
      return -1
    }
  }
  @objc public func readData(completion: @escaping (Data, String?, Bool) -> Void) {
    connection.receive(minimumIncompleteLength: 0, maximumLength: 65536) {
      (data, _, isComplete, error) in
      guard let content = data else {
        completion(Data(count: 0), error?.debugDescription, isComplete)
        return
      }
      completion(content, error?.debugDescription, isComplete)
    }
  }

  @objc public func writeData(buffer: Data, completion: @escaping (Int, String?) -> Void) {
    let byteCount = buffer.count
    connection.send(
      content: buffer,
      completion: .contentProcessed { error in
        if error != nil {
          completion(0, error?.debugDescription)
        } else {
          completion(byteCount, error?.debugDescription)
        }
      })
  }

  @objc public func cancel() {
    connection.cancel()
  }

  @objc public func forceCancel() {
    connection.forceCancel()
  }
}

@objc
public class PortHelper: NSObject {
  @objc public func isPortOpen(actualPort: Int) -> Bool {
    let port = UInt16(actualPort)
    let socketFileDescriptor = socket(AF_INET, SOCK_STREAM, 0)
    if socketFileDescriptor == -1 {
      return false
    }

    var addr = sockaddr_in()
    let sizeOfSockkAddr = MemoryLayout<sockaddr_in>.size
    addr.sin_len = __uint8_t(sizeOfSockkAddr)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = Int(OSHostByteOrder()) == OSLittleEndian ? _OSSwapInt16(port) : port
    addr.sin_addr = in_addr(s_addr: inet_addr("0.0.0.0"))
    addr.sin_zero = (0, 0, 0, 0, 0, 0, 0, 0)
    var bind_addr = sockaddr()
    memcpy(&bind_addr, &addr, Int(sizeOfSockkAddr))

    if Darwin.bind(socketFileDescriptor, &bind_addr, socklen_t(sizeOfSockkAddr)) == -1 {
      return false
    }
    let isOpen = listen(socketFileDescriptor, SOMAXCONN) != -1
    Darwin.close(socketFileDescriptor)
    return isOpen
  }
}
