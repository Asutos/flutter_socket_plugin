import Flutter
import UIKit
import CocoaAsyncSocket 

// MARK: Flutter socket plugin
public class SwiftFlutterSocketPlugin: NSObject, FlutterPlugin {
    
    var registrar: FlutterPluginRegistrar
    
    /// init function
    ///
    /// - Parameter _registrar: FlutterPluginRegistrar
    init(_ _registrar: FlutterPluginRegistrar){
        registrar = _registrar
    }
    
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_socket_plugin", binaryMessenger: registrar.messenger())
    let instance = SwiftFlutterSocketPlugin(registrar)
    registrar.addMethodCallDelegate(instance, channel: channel)
    FlutterSocket.sharedInstance.createChannel(registrar: registrar)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "create_socket" {
        if let arguments = call.arguments {
            let dic = arguments as! [String:Any]
            let host = dic["host"]
            let port = dic["port"]
            let timeout = dic["timeout"]
            if host == nil || port == nil {
                let str = EncoderTool.encodeWithDictionary(dictionary: ["error_message":"Host or port is required."])
                FlutterSocket.sharedInstance.invoke(methodName: "error", arguments: str)
            } else {
                FlutterSocket.sharedInstance.host = host as? String
                FlutterSocket.sharedInstance.port = UInt16(port as! Int)
                FlutterSocket.sharedInstance.timeout = timeout == nil ? 20 : (timeout as! TimeInterval)
                FlutterSocket.sharedInstance.createSocket()
            }
        } else {
            let str = EncoderTool.encodeWithDictionary(dictionary: ["error_message":"Host or port is required."])
            FlutterSocket.sharedInstance.invoke(methodName: "error", arguments: str)
        }
    } else if call.method == "try_connect" {
        
        FlutterSocket.sharedInstance.tryConnect(host: FlutterSocket.sharedInstance.host, port: FlutterSocket.sharedInstance.port, timeout: FlutterSocket.sharedInstance.timeout)
        
    } else if call.method == "send_message" {
        if let arguments = call.arguments {
            let dic = arguments as! [String:Any]
            let message = dic["message"]
            if message == nil {
                let str = EncoderTool.encodeWithDictionary(dictionary: ["error_message":"Sending content cannot be empty."])
                FlutterSocket.sharedInstance.invoke(methodName: "error", arguments: str)
            } else {
                FlutterSocket.sharedInstance.send(message: message as! String)
            }
        } else {
            let str = EncoderTool.encodeWithDictionary(dictionary: ["error_message":"Sending content cannot be empty."])
            FlutterSocket.sharedInstance.invoke(methodName: "error", arguments: str)
        }
    } else if call.method == "try_disconnect" {
        FlutterSocket.sharedInstance.tryDisconnect()
    }
  }
}

// MARK: Flutter socket class
class FlutterSocket:NSObject, GCDAsyncSocketDelegate {

    /// 单例
    static let sharedInstance = FlutterSocket()

    fileprivate var receiveBuf:Data!

    /// 是否连接
    var connected:Bool = false

    /// GCDAsyncSocket
    var socket:GCDAsyncSocket!
    


    /// method channel
    var methodChannel:FlutterMethodChannel!
    
    /// host
    var host:String!
    
    /// port
    var port:UInt16!
    
    /// timeout
    var timeout:TimeInterval = 30
    
    private override init() {}

    
    /// create method channel
    ///
    /// - Parameter registrar: FlutterPluginRegistrar
    public func createChannel(registrar: FlutterPluginRegistrar) -> Void {
        if methodChannel == nil {
            methodChannel = FlutterMethodChannel(name: "flutter_socket_plugin", binaryMessenger: registrar.messenger())
        }
    }
    
    
    /// create socket
    ///
    /// - Returns: create is successful
    public func createSocket() -> Void {
        if socket == nil {
            socket = GCDAsyncSocket(delegate: self, delegateQueue: DispatchQueue.main)
        }
    }

    /// try connect to socket 
    ///
    /// - Parameters:
    ///   - host: host,usually ip address or domain
    ///   - port: port type is UInt16
    ///   - timeout: timeout default 30s
    public func tryConnect(host:String,port:UInt16,timeout:TimeInterval) -> Void {
        if socket != nil {
            do {
                try socket.connect(toHost: host, onPort: port, viaInterface: nil, withTimeout: timeout)
            } catch (let error) {
                print(error)
                let str = EncoderTool.encodeWithDictionary(dictionary: ["error_message":error.localizedDescription])
                invoke(methodName: "error", arguments: str)
                connected = false
            }
        } else {
            connected = false
        }
    }

    /// try disconnect to socket
    public func tryDisconnect() -> Void {
        if socket != nil {
            socket.disconnect()
        } else {
            connected = false
        }
    }

    /// send message only support string type at this time
    ///
    /// - Parameter message: message
    public func send(message:String) -> Void {
        if connected {
            
            let contentData:Data = message.data(using: String.Encoding.utf8)!
            let value:Int = contentData.count
            
            var byteData:[UInt8] = []
            let byte_0:UInt8 = UInt8((value & 0xFF000000) >> 24)
            let byte_1:UInt8 = UInt8((value & 0xFF0000) >> 16)
            let byte_2:UInt8 = UInt8((value & 0xFF00) >> 8)
            let byte_3:UInt8 = UInt8((value & 0xFF))
            byteData.append(byte_0)
            byteData.append(byte_1)
            byteData.append(byte_2)
            byteData.append(byte_3)
            
            let headData = Data(byteData)
            let send_data = NSMutableData()
            send_data.append(headData)
            send_data.append(contentData)
            
            socket.write(send_data as Data, withTimeout: -1, tag: 0)
        }
    }
    
    /// ios invokes flutter method and transfers arguments
    ///
    /// - Parameters:
    ///   - methodName: methodName 
    ///   - arguments: arguments
    public func invoke(methodName:String,arguments:String) -> Void {
        methodChannel.invokeMethod(methodName, arguments: arguments)
    }
    


    
    
    
    
    /// GCDAsyncSocket didConnect call back
    ///
    /// - Parameters:
    ///   - sock: GCDAsyncSocket
    ///   - host: host
    ///   - port: port
    func socket(_ sock: GCDAsyncSocket, didConnectToHost host: String, port: UInt16) {
        connected = true
        receiveBuf = Data(capacity: 1024*1024)
        socket.readData(withTimeout: -1, tag: 0)
        methodChannel.invokeMethod("connected", arguments: "connected")
    }
    
    /// GCDAsyncSocket didRead call back
    ///
    /// - Parameters:
    ///   - sock: GCDAsyncSocket
    ///   - data: data
    ///   - tag: tag
    func socket(_ sock: GCDAsyncSocket, didRead data: Data, withTag tag: Int) {
        let dataCount = data.count
        let originMsg = String(data:data,encoding: String.Encoding.utf8)
        if(dataCount>0) {
            print("read messageLength :\(dataCount),message is : \(originMsg)")

            resolve(data: data)
        }

        socket.readData(withTimeout: -1, tag: 0)
    }

    func resolve(data:Data) -> Void {
//         print("read messageLength :\(dataCount),message is : \(originMsg!)")
        receiveBuf.append(data)

        while(true) {
            let count = receiveBuf.count
//            let bufferMsg = String(data:receiveBuf,encoding: String.Encoding.utf8)
//            print("buffer length:  \(count) ,buffer msg:\(bufferMsg!)")
            if(count > 4) {
                let bodyLen = UInt32(receiveBuf[0]) << 24 + UInt32(receiveBuf[1]) << 16 + UInt32(receiveBuf[2]) << 8 + UInt32(receiveBuf[3])

                let msgLength = Int(bodyLen)+4
//                 print("bufferLenth : \(count), bodyLength : \(bodyLen), msgLength : \(msgLength)")
                if( count >= msgLength ){
                    let message = String(data: receiveBuf.subdata(in: 4..<msgLength),encoding: String.Encoding.utf8)
//                    print("send message to flutter : \(message!)")
                    methodChannel.invokeMethod("receive_message", arguments: message)

                    if(count > msgLength) {
//                        let resetData = receiveBuf.subdata(in: msgLength ..< count)
//                        receiveBuf.replaceSubrange(0 ..< resetData.count, with: resetData)
                        receiveBuf.removeSubrange(0 ..< msgLength)
                    }else if (count == msgLength) {
                        receiveBuf.removeAll(keepingCapacity: false)
                    } else {
                        print("some else ")
                    }
//                    receiveBuf.removeSubrange(0 ..< msgLength)

                } else {
                    break
                }
            }else {
                break
            }
        }
    }

    /// GCDAsyncSocket didDisconnect call back
    ///
    /// - Parameters:
    ///   - sock: GCDAsyncSocket
    ///   - err: error
    func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: Error?) {
        socket.delegate = nil
        socket = nil
        connected = false
        if(receiveBuf != nil){
            receiveBuf.removeAll()
            receiveBuf = nil
        }

        methodChannel.invokeMethod("disconnect", arguments: "disconnected")
    }

}

// MARK: encoder dictionary to json string
class EncoderTool: NSObject {
    
    /// dictionary to json
    ///
    /// - Parameter dictionary: dictionary
    /// - Returns: json string
    static func encodeWithDictionary(dictionary:[String:Any]) -> String {
        if (!JSONSerialization.isValidJSONObject(dictionary)) {
            return ""
        }
        if let jsonData = try? JSONSerialization.data(
            withJSONObject: dictionary, 
            options: []) {
            let jsonString = String(data: jsonData, encoding: String.Encoding.utf8)
            if let str = jsonString {
                return str
            } else {
                return ""
            }
        } else {
            return ""
        }
    }
}
