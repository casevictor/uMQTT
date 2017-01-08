//
//  uMQTT
//  uMQTTClientApp
//
//  Created by Victor Casé on 6/3/16.
//  Copyright © 2016 Victor Casé. All rights reserved.
//

import Foundation
import CFNetwork

extension String {
    var twoBytesLength: [UInt8] { return UInt16(utf8.count).highestLowest + utf8}
    var bytes: [UInt8] { return utf8 + []}
}

extension UInt16 {
    var MSB : UInt8 { return UInt8((self & 0b1111111100000000) >> 8)}
    var LSB : UInt8 { return UInt8((self & 0b0000000011111111))}
    var highestLowest: [UInt8] { return [MSB,LSB] }
}

extension UInt8 {
    var MSB : UInt8 { return UInt8((self & 0b11110000) >> 4)}
    var LSB : UInt8 { return UInt8((self & 0b00001111))}
}

extension Bool {
    var bit : UInt8 { return self ? 1 : 0 }
    
    init(bit: UInt8){
        self = (bit == 0) ? false : true
    }
}

extension OutputStream {
    
    func writeData(_ data: [UInt8]) -> Int {
        let size = data.count
        var completed = 0
        while completed < size {
            let wrote = write(UnsafePointer(data) + completed, maxLength:size - completed)
            if wrote < 0 {
                return wrote
            } else {
                completed += wrote
            }
        }
        return completed
    }
}

//MQTT v3.1.1
enum uMQTTControlFrameType : UInt8 {
    case reserved    = 0b00000000
    case connect     = 0b00010000
    case connack     = 0b00100000
    case publish     = 0b00110000
    case puback      = 0b01000000
    case pubrec      = 0b01010000
    case pubrel      = 0b01100000
    case pubcomp     = 0b01110000
    case subscribe   = 0b10000000
    case suback      = 0b10010000
    case unsubscribe = 0b10100000
    case unsuback    = 0b10110000
    case pingreq     = 0b11000000
    case pingresp    = 0b11010000
    case disconnect  = 0b11100000
}

enum ClientStatus : UInt8 {
    case unpack_HEADER  =   1
    case unpack_LENGTH  =   2
    case unpack_VHEADER_PAYLOAD = 3
}

enum CONNACKReturnCode : UInt8 {
    case accepted           = 0b00000000
    case wrong_PROTOCOL     = 0b00000001
    case id_REJECTED        = 0b00000010
    case server_UNAVAILABLE = 0b00000011
    case bad_CREDENTIALS    = 0b00000100
    case not_AUTHORIZED     = 0b00000101
}

enum QOS : UInt8 {
    case qos0 = 0b00000000
    case qos1 = 0b00000001
    case qos2 = 0b00000010
}

enum SUBACKReturnCode : UInt8 {
    case maxQoS0 = 0b00000000
    case maxQoS1 = 0b00000001
    case maxQoS2 = 0b00000010
    case failure = 0b10000000
}

protocol uMQTTDelegate: class {
    func didConnectedWithSuccess(_ message:String)
    func didConnectedWithError(_ message:String)
    func didReceivedMessage(_ message: String, type:uMQTTControlFrameType)
    func didSendMessage(_ message:String)
    func readyToSendMessage()
    func didConnectionErrorOcurred()
}

private class uMQTTClient {
    var status : ClientStatus
    var currentFrame : uMQTTControlFrameType
    var currentRemainingLength : Int = 0
    var currentFrameFlags : UInt8 = 0b00000000
    
    init(){
        status = ClientStatus.unpack_HEADER
        currentFrame = .reserved
    }
}

class uMQTT : NSObject, StreamDelegate {
    
    fileprivate var queue = DispatchQueue(label: "your.acme.mqtt", attributes: [])
    
    fileprivate var host: CFString
    fileprivate var port: UInt32
    
    fileprivate var inputStream: InputStream!
    fileprivate var outputStream: OutputStream!
    fileprivate var readBuffer = [UInt8](repeating: 0, count: 92160)
    fileprivate var readBufferLength : Int = 1
    
    fileprivate var multiplier : Int = 1
    fileprivate var value : Int = 0
    
    fileprivate var client: uMQTTClient
    weak var delegate: uMQTTDelegate?
    
    fileprivate var keepAliveTimer: Timer!
    var keepAliveInterval: UInt16 = 170
    fileprivate var timer: DispatchSource! = nil
    
    var bytesRead = 0
    var completed = 0
    
    
    init(host: String = "85.119.83.194", atPort:UInt32 = 1883){ // IP points to http://test.mosquitto.org/
        self.host = host as CFString
        self.port = atPort
        self.client = uMQTTClient()
        super.init()
        self.openMQTTSocket()
    }
    
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        if aStream == inputStream {
            switch eventCode {
            case Stream.Event.errorOccurred:
                print("(input) ErrorOcurred: \(aStream.streamError) ")
                self.delegate!.didConnectionErrorOcurred()
            case Stream.Event.openCompleted:
                print("(input) OpenCompleted")
            case Stream.Event.hasBytesAvailable:
                print("(input) HasBytesAvailable")
                
                queue.async {
                    self.bytesRead = self.inputStream!.read(UnsafeMutablePointer(mutating: self.readBuffer) + self.completed, maxLength: self.readBufferLength - self.completed)
                    self.completed += self.bytesRead
                    
                    if(self.completed < self.readBufferLength){
                        return;
                    }else{
                        self.bytesRead = 0
                        self.completed = 0
                    }
                    
                    switch self.client.status {
                    case .unpack_HEADER:
                        self.unwrapFrame(self.readBuffer[0])
                        break
                        
                    case .unpack_LENGTH:
                        self.unwrapFrame(self.readBuffer[0])
                        break
                    case .unpack_VHEADER_PAYLOAD:
                        self.unwrapPayload(self.readBuffer)
                        break
                    }
                }
            default:
                break
            }
        }else if aStream == outputStream {
            switch eventCode {
            case Stream.Event.errorOccurred:
                print("(output) ErrorOcurred: \(aStream.streamError)")
            case Stream.Event.openCompleted:
                print("(output) OpenCompleted")
            case Stream.Event.hasSpaceAvailable:
                print("(output) HasSpaceAvailable")
            default:
                break
            }
        }else{
            print("Neither inputStream or outputStream")
        }
    }
    
    func connectSocket(_ host:String, port:UInt32) {
        var readStream  : Unmanaged<CFReadStream>?
        var writeStream : Unmanaged<CFWriteStream>?
        
        CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault, self.host, self.port, &readStream, &writeStream);
        
        inputStream = readStream!.takeRetainedValue()
        outputStream = writeStream!.takeRetainedValue()
        
        inputStream.delegate = self
        outputStream.delegate = self
        
        inputStream.open()
        outputStream.open()
        
        inputStream.schedule(in: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
        outputStream.schedule(in: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
    }
    
    func disconnectSocket() {
        for stream in [inputStream,outputStream] as [Any]{
            (stream as AnyObject).close()
        }
    }
    
    func openMQTTSocket() -> () {
        self.connectSocket(self.host as String, port: self.port)
        self.startKeepAliveTimer()
    }
    
    func connect(_ username: String? = nil, password: String? = nil) -> () {
        let frame : uMQTTConnectFrame = uMQTTConnectFrame(username: username, password: password)
        let bytesToWire = frame.buildFrame()
        self.outputStream!.write(bytesToWire, maxLength: bytesToWire.count)
    }
    
    func disconnect() -> () {
        let frame : uMQTTDisconnectFrame = uMQTTDisconnectFrame()
        let bytesToWire = frame.buildFrame()
        self.outputStream!.write(bytesToWire, maxLength: bytesToWire.count)
    }
    
    func subscribe(_ topic: String) -> () {
        let frame : uMQTTSubscribeFrame = uMQTTSubscribeFrame(topic: topic)
        let bytesToWire = frame.buildFrame()
        self.outputStream!.write(bytesToWire, maxLength: bytesToWire.count)
    }
    
    func unsubscribe(_ topic: String) -> () {
        let frame : uMQTTUnsubscribeFrame = uMQTTUnsubscribeFrame(topic: topic)
        let bytesToWire = frame.buildFrame()
        self.outputStream!.write(bytesToWire, maxLength: bytesToWire.count)
        
    }
    
    func publish(_ topic: String, payload: String, qos: UInt8 = 0, ret: Bool = false) -> () {
        queue.async {
            let frame : uMQTTPublishFrame = uMQTTPublishFrame(topic: topic, payload: payload, dup: false, qos: qos, ret: ret)
            let bytesToWire = frame.buildFrame()
            if(self.outputStream.streamStatus == .open){
                let writtenBytes = self.outputStream!.writeData(bytesToWire)
            }
        }
    }
    
    func puback(_ packetIdentifier: UInt16) -> (){
        let frame : uMQTTPUBACKFrame = uMQTTPUBACKFrame(packetIdentifier: packetIdentifier)
        let bytesToWire = frame.buildFrame()
        self.outputStream!.write(bytesToWire, maxLength: bytesToWire.count)
    }
    
    func ping() -> () {
        let frame : uMQTTPing = uMQTTPing()
        let bytesToWire = frame.buildFrame()
        self.outputStream!.write(UnsafePointer(bytesToWire), maxLength: bytesToWire.count)
    }
    
    fileprivate func unwrapPayload(_ frame:[UInt8]) -> () {
        switch client.currentFrame {
        case .connack:
            switch frame[1] {
            case CONNACKReturnCode.accepted.rawValue:
                self.delegate!.didConnectedWithSuccess("Connection Accepted!")
            case CONNACKReturnCode.wrong_PROTOCOL.rawValue:
                self.delegate!.didConnectedWithError("Connection Refused, Wrong Protocol Version")
            case CONNACKReturnCode.id_REJECTED.rawValue:
                self.delegate!.didConnectedWithError("Connection Refused, Client ID Rejected")
            case CONNACKReturnCode.server_UNAVAILABLE.rawValue:
                self.delegate!.didConnectedWithError("Connection Refused, Server Unavailable")
            case CONNACKReturnCode.bad_CREDENTIALS.rawValue:
                self.delegate!.didConnectedWithError("Connection Refused, Bad Credentials")
            case CONNACKReturnCode.not_AUTHORIZED.rawValue:
                self.delegate!.didConnectedWithError("Connection Refused, Not Authorized")
            default:
                print("Payload not recognized")
            }
        case .suback:
            switch frame[3] {
            case SUBACKReturnCode.maxQoS0.rawValue:
                print("Success - Maximum QoS 0")
            case SUBACKReturnCode.maxQoS1.rawValue:
                print("Success - Maximum QoS 1")
            case SUBACKReturnCode.maxQoS2.rawValue:
                print("Success - Maximum QoS 2")
            case SUBACKReturnCode.failure.rawValue:
                print("Failure")
            default:
                print("Payload not recognized")
            }
            print("-- Packet Identifier -- \(frame[0]) \(frame[1])")
        case .publish:
            let dup = (client.currentFrameFlags & 0b00001000) >> 3
            let qos = (client.currentFrameFlags & 0b00000110) >> 1
            let ret = (client.currentFrameFlags & 0b00000001)
            
            let topic_len = (Int)(frame[1] | frame[0] << 4)
            var packetIdentifier : UInt16 = 0
            
            let payload_len = (Int)(client.currentRemainingLength)
            var startIndex = 2
            if let topic = String(bytes: frame[startIndex..<(startIndex+topic_len)], encoding: String.Encoding.utf8) {
                print(topic)
                
                if qos != 0b00000000 {
                    packetIdentifier = ((UInt16)(frame[(startIndex+topic_len)]) << 8) | (UInt16)(frame[(startIndex+topic_len)+1] & 0b0000000011111111)
                    startIndex = (startIndex+topic_len)+2
                }else{
                    startIndex = (startIndex+topic_len)
                }
                
                switch qos {
                case QOS.qos0.rawValue:
                    print("None")
                case QOS.qos1.rawValue:
                    print("Send a PUBACK Packet with packetID = \(packetIdentifier)")
                    self.puback(packetIdentifier)
                case QOS.qos2.rawValue:
                    print("Send a PUBREC Packet")
                default:
                    break
                }
                
                if ( payload_len > startIndex ) {
                    let payload : String = String(bytes: frame[startIndex..<payload_len], encoding:String.Encoding.utf8)!
                    
                    print("PUBLISH TOPIC = \(topic) with Length = \(topic_len)")
                    print("PACKET ID = \(packetIdentifier)")
                    print("PAYLOAD = \(payload)")
                    print("DUP = \(dup)")
                    print("RET = \(ret)")
                    
                    self.delegate!.didReceivedMessage(payload, type: .publish)
                    
                }
            }
            
        case .unsuback:
            let packetIdentifier = ((UInt16)(frame[0]) << 8) | (UInt16)(frame[1] & 0b0000000011111111)
            print("PACKET ID = \(packetIdentifier)")
        default:
            break;
        }
        
        readBufferLength = 1
        self.client.status = .unpack_HEADER
    }
    
    fileprivate func unwrapFrame(_ frame:UInt8) -> () {
        switch client.status {
        case .unpack_HEADER:
            switch (frame & 0b11110000) {
            case uMQTTControlFrameType.connack.rawValue:
                print("CONNACK Received")
                client.currentFrame = .connack
            case uMQTTControlFrameType.pingresp.rawValue:
                print("PINGRESP Received")
                client.currentFrame = .pingresp
            case uMQTTControlFrameType.suback.rawValue:
                print("SUBACK Received")
                client.currentFrame = .suback
            case uMQTTControlFrameType.publish.rawValue:
                print("PUBLISH Received")
                client.currentFrame = .publish
            case uMQTTControlFrameType.unsuback.rawValue:
                print("UNSUBACK Received")
                client.currentFrame = .unsuback
            case uMQTTControlFrameType.puback.rawValue:
                print("PUBACK Received")
                client.currentFrame = .puback
            default:
                print("Unkown Header")
                client.status = .unpack_HEADER
                return
            }
            client.currentFrameFlags = frame & 0b00001111
            client.status = .unpack_LENGTH
        case .unpack_LENGTH:
            print("Lenght = \(frame)")
            let encodedByte = (Int)(frame)
            self.value += (encodedByte & 127) * self.multiplier
            self.multiplier *= 128
            
            if(self.multiplier > 128*128*128){
                print("Malformated Remaining Length")
                return
            }
            
            if((encodedByte & 128) != 0){
                client.status = .unpack_LENGTH
                return
            }
            
            client.currentRemainingLength = value
            readBufferLength = value
            
            self.multiplier = 1
            self.value = 0
            
            if(readBufferLength == 0){
                readBufferLength = 1
                client.status = .unpack_HEADER
            }else{
                client.status = .unpack_VHEADER_PAYLOAD
            }
        case .unpack_VHEADER_PAYLOAD:
            break
        }
    }
    
   
    fileprivate func startKeepAliveTimer() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = Timer.scheduledTimer(
            timeInterval: Double(keepAliveInterval) / 2.0,
            target: self,
            selector: #selector(self.ping),
            userInfo: nil,
            repeats: true)
    }
    
    fileprivate func endKeepAliveTimer() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }
    
    
}

/**
 MQTT Control Packet Frame v3.1.1
 bits [7 6 5 4] -> Type
 bits [3]       -> (DUP) Duplicate delivery of a PUBLISH Control Packet
 bits [2 1]     -> (QOS) PUBLISH Quality of Service
 bits [0]       -> (RET) PUBLISH Retain flag
 **/

private class uMQTTFrame {
    var fixedHeader : UInt8 = 0
    var controlPacketType : UInt8 {return UInt8(fixedHeader & 0b11110000)}
    var variableHeader : [UInt8] = []
    var payload :[UInt8] = []
    var packetId : UInt16 = 1
    
    init(controlFrameType: uMQTTControlFrameType, flags:UInt8 = 0b00000000, payload: [UInt8] = []){
        self.fixedHeader = controlFrameType.rawValue | flags
    }
    
    func buildVariableHeader() -> (){
        return;
    }
    
    func buildPayload() -> (){
        return;
    }
    
    func buildFrame() -> [UInt8] {
        return [UInt8]([fixedHeader]) + encodedLength() + variableHeader + payload
    };
    
    func encodedLength() -> [UInt8] {
        var byte : UInt8 = 0
        var remainingLength = (Int)(self.variableHeader.count + self.payload.count)
        var encodedRemainingLength : [UInt8] = []
        repeat {
            byte = UInt8((remainingLength % 128))
            remainingLength = remainingLength / 128
            if( remainingLength > 0){
                byte = byte | 128
            }
            encodedRemainingLength.append(byte)
        } while( remainingLength > 0 )
        return encodedRemainingLength
    }
    
    fileprivate func generatePacketId() -> UInt16 {
        self.packetId += 1
        let nextId = self.packetId
        if (nextId >= UInt16.max) { self.packetId = 1 }
        return nextId
    }
    
    
}

private class uMQTTPing : uMQTTFrame {
    init() {
        super.init(controlFrameType: uMQTTControlFrameType.pingreq)
    }
}

private class uMQTTConnectFrame : uMQTTFrame {
    
    let MQTT : String = "MQTT"
    var clientUsername : String = ""
    var clientPassword : String = ""
    let clientTopic : String = "a/b"
    let clientMessage : String = "Disconnect"
    let clientKeepAlive : UInt16 = 180
    let userDefaults = UserDefaults.standard
    
    var connectedFlags : UInt8 = 0
    var username : Bool {
        get { return Bool(bit:(connectedFlags >> 7) & 0b00000001)}
        set { connectedFlags |= (newValue.bit << 7)}
    }
    var password : Bool {
        get { return Bool(bit:(connectedFlags >> 6) & 0b0000001)}
        set { connectedFlags |= (newValue.bit << 6)}
    }
    var willRetain : Bool {
        get { return Bool(bit:(connectedFlags >> 5) & 0b0000001)}
        set { connectedFlags |= (newValue.bit << 5)}
    }
    var willQoS : UInt8 {
        get { return (connectedFlags >> 3) & 0b00000011}
        set { connectedFlags |= (newValue << 3)}
    }
    
    var will : Bool {
        get { return Bool(bit:(connectedFlags >> 2) & 0b0000001)}
        set { connectedFlags |= (newValue.bit << 2)}
    }
    var cleanSession : Bool {
        get { return Bool(bit:(connectedFlags >> 1) & 0b0000001)}
        set { connectedFlags |= (newValue.bit << 1)}
    }
    
    init(username:String?, password: String?, will: Bool = true, willRetain: Bool = false, willQoS: UInt8 = 0b000000001, cleanSession: Bool = false){
        super.init(controlFrameType: uMQTTControlFrameType.connect)
        if let username = username {
            self.clientUsername = username
            self.username = true
        }
        if let password = password {
            self.clientPassword = password
            self.password = true
        }
        self.buildVariableHeader()
        self.buildFlags(self.username, password: self.password, willRetain: willRetain, willQoS: willQoS, will: will, cleanSession: cleanSession)
        self.buildKeepAlive()
        self.buildPayload()
    }
    
    override func buildVariableHeader() -> () {
        self.variableHeader += MQTT.twoBytesLength
        self.variableHeader.append(0b00000100) // Protocol Label Byte
    }
    
    func buildFlags(_ username: Bool, password: Bool, willRetain: Bool, willQoS: UInt8, will: Bool, cleanSession:Bool) -> () {
        self.username = username
        self.password = password
        self.willRetain = willRetain
        self.willQoS = willQoS
        self.will = will
        self.cleanSession = cleanSession
        self.variableHeader.append(self.connectedFlags)
    }
    
    func buildKeepAlive() -> () {
        self.variableHeader += self.clientKeepAlive.highestLowest
    }
    
    override func buildPayload() -> () {
        self.payload += (userDefaults.object(forKey: "mqttClientId") as! String).twoBytesLength
        self.payload += clientTopic.twoBytesLength
        self.payload += clientMessage.twoBytesLength
        if (self.username) {self.payload += clientUsername.twoBytesLength}
        if (self.password) {self.payload += clientPassword.twoBytesLength}
    }
}

private class uMQTTSubscribeFrame: uMQTTFrame {
    
    var requestedQoS : UInt8 = 0b0000001
    
    init(topic: String){
        super.init(controlFrameType: uMQTTControlFrameType.subscribe, flags:0b00000010)
        self.packetId = self.generatePacketId()
        self.buildVariableHeader()
        self.buildPayload(topic)
    }
    
    override func buildVariableHeader() {
        self.variableHeader += self.packetId.highestLowest
    }
    
    func buildPayload(_ topic: String) {
        super.buildPayload()
        self.payload += topic.twoBytesLength
        self.payload.append(requestedQoS)
    }
    
}

private class uMQTTUnsubscribeFrame: uMQTTFrame {
    init(topic: String){
        super.init(controlFrameType: uMQTTControlFrameType.unsubscribe, flags:0b00000010)
        self.buildVariableHeader()
        self.buildPayload(topic)
    }
    
    override func buildVariableHeader() {
        self.packetId = self.generatePacketId()
        super.variableHeader += self.packetId.highestLowest
    }
    
    func buildPayload(_ topic: String) {
        super.buildPayload()
        self.payload += topic.twoBytesLength
    }
    
}

private class uMQTTPublishFrame: uMQTTFrame {
    
    var controlPacketFlags : UInt8 = 0b00000000
    
    var dup : Bool {
        get { return Bool(bit:(controlPacketFlags >> 3 ) & 0b0000001)}
        set { controlPacketFlags |= (newValue.bit << 3)}
    }
    var qos : UInt8 {
        get { return (controlPacketFlags >> 1) & 0b00000011}
        set { controlPacketFlags |= (newValue << 1)}
    }
    
    var ret : Bool {
        get { return Bool(bit:(controlPacketFlags & 0b00000001))}
        set {controlPacketFlags |= (newValue.bit)}
    }
    
    init(topic:String, payload: String, dup: Bool, qos:UInt8, ret:Bool){
        super.init(controlFrameType:.publish)
        self.buildFlags(dup, qos: qos, ret: ret)
        self.buildVariableHeader(topic)
        self.buildPayload(payload)
    }
    
    func buildFlags(_ dup:Bool, qos:UInt8, ret:Bool) -> (){
        self.dup = dup
        self.qos = qos
        self.ret = ret
        self.fixedHeader |= controlPacketFlags
    }
    
    func buildVariableHeader(_ topic:String) {
        self.variableHeader += topic.twoBytesLength
        if(qos != 0b00000000){
            self.variableHeader += generatePacketId().highestLowest
        }
    }
    
    func buildPayload(_ payload:String) {
        self.payload += payload.bytes
    }
}

private class uMQTTPUBACKFrame: uMQTTFrame {
    
    init(packetIdentifier: UInt16){
        super.init(controlFrameType: uMQTTControlFrameType.puback)
        packetId = packetIdentifier
        self.buildVariableHeader()
        self.buildPayload()
        
    }
    
    override func buildVariableHeader() {
        self.variableHeader += self.packetId.highestLowest
    }
}

private class uMQTTPUBRECFrame: uMQTTFrame {
    init(packetIdentifier: UInt16){
        super.init(controlFrameType: uMQTTControlFrameType.pubrec)
        packetId = packetIdentifier
        self.buildVariableHeader()
        self.buildPayload()
    }
    
    override func buildVariableHeader() {
        self.variableHeader += self.packetId.highestLowest
    }
}

private class uMQTTDisconnectFrame: uMQTTFrame {
    init(){
        super.init(controlFrameType: uMQTTControlFrameType.disconnect)
        self.buildVariableHeader()
        self.buildPayload()
    }
}
