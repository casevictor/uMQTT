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

//MQTT v3.1.1
enum uMQTTControlFrameType : UInt8 {
    case RESERVED    = 0b00000000
    case CONNECT     = 0b00010000
    case CONNACK     = 0b00100000
    case PUBLISH     = 0b00110000
    case PUBACK      = 0b01000000
    case PUBREC      = 0b01010000
    case PUBREL      = 0b01100000
    case PUBCOMP     = 0b01110000
    case SUBSCRIBE   = 0b10000000
    case SUBACK      = 0b10010000
    case UNSUBSCRIBE = 0b10100000
    case UNSUBACK    = 0b10110000
    case PINGREQ     = 0b11000000
    case PINGRESP    = 0b11010000
    case DISCONNECT  = 0b11100000
}

enum ClientStatus : UInt8 {
    case UNPACK_HEADER  =   1
    case UNPACK_LENGTH  =   2
    case UNPACK_VHEADER_PAYLOAD = 3
}

enum CONNACKReturnCode : UInt8 {
    case ACCEPTED           = 0b00000000
    case WRONG_PROTOCOL     = 0b00000001
    case ID_REJECTED        = 0b00000010
    case SERVER_UNAVAILABLE = 0b00000011
    case BAD_CREDENTIALS    = 0b00000100
    case NOT_AUTHORIZED     = 0b00000101
}

enum QOS : UInt8 {
    case QOS0 = 0b00000000
    case QOS1 = 0b00000001
    case QOS2 = 0b00000010
}

enum SUBACKReturnCode : UInt8 {
    case MAXQoS0 = 0b00000000
    case MAXQoS1 = 0b00000001
    case MAXQoS2 = 0b00000010
    case Failure = 0b10000000
}

protocol uMQTTDelegate: class {
    func didReceivedMessage(message: String, type:uMQTTControlFrameType)
    func didSendMessage(message:String)
    func readyToSendMessage()
}

private class uMQTTClient {
    var status : ClientStatus
    var currentFrame : uMQTTControlFrameType
    var currentRemainingLength : UInt8 = 0
    var currentFrameFlags : UInt8 = 0b00000000
    
    init(){
        status = ClientStatus.UNPACK_HEADER
        currentFrame = .RESERVED
    }
}

class uMQTT : NSObject, NSStreamDelegate {
    private var inputStream: NSInputStream!
    private var outputStream: NSOutputStream!
    private var readBuffer = [UInt8](count: 1024, repeatedValue: 0)
    private var readBufferLength : Int = 1
    private var host: CFString
    private var port: UInt32
    private var client: uMQTTClient
    weak var delegate: uMQTTDelegate?
    private var keepAliveTimer: NSTimer!
    var keepAliveInterval: UInt16 = 60
    
    init(host: String = "85.119.83.194", atPort:UInt32 = 1883){ // IP points to http://test.mosquitto.org/
        self.host = host
        self.port = atPort
        self.client = uMQTTClient()
        super.init()
        self.openMQTTSocket()
    }
    
    func stream(aStream: NSStream, handleEvent eventCode: NSStreamEvent) {
        if aStream == inputStream {
            switch eventCode {
            case NSStreamEvent.ErrorOccurred:
                print("(input) ErrorOcurred: \(aStream.streamError?.description) ")
                
            case NSStreamEvent.OpenCompleted:
                print("(input) OpenCompleted")
            case NSStreamEvent.HasBytesAvailable:
                print("(input) HasBytesAvailable")
                
                readBuffer = [UInt8](count: 1024, repeatedValue: 0)
                let numBytes = inputStream!.read(&readBuffer, maxLength: readBufferLength)
                print("\(numBytes) was read")
                
                switch client.status {
                case .UNPACK_HEADER:
                    self.unwrapFrame(readBuffer[0])
                    break
                case .UNPACK_LENGTH:
                    self.unwrapFrame(readBuffer[0])
                    break
                case .UNPACK_VHEADER_PAYLOAD:
                    self.unwrapPayload(readBuffer)
                    break
                }
            default:
                break
            }
        }else if aStream == outputStream {
            switch eventCode {
            case NSStreamEvent.ErrorOccurred:
                print("(output) ErrorOcurred: \(aStream.streamError?.description)")
                self.reopenMQTTSocket()
            case NSStreamEvent.OpenCompleted:
                print("(output) OpenCompleted")
            case NSStreamEvent.HasSpaceAvailable:
                print("(output) HasSpaceAvailable")
            default:
                break
            }
        }else{
            print("Neither inputStream or outputStream")
        }
    }
    
    func connectSocket(host:String, port:UInt32) -> Bool {
        var readStream  : Unmanaged<CFReadStream>?
        var writeStream : Unmanaged<CFWriteStream>?
        
        CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault, self.host, self.port, &readStream, &writeStream);
        
        inputStream = readStream!.takeRetainedValue()
        outputStream = writeStream!.takeRetainedValue()
        
        for stream in [inputStream, outputStream]{
            stream.delegate = self
            stream.open()
            stream.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        }
        return true
        
    }
    
    func disconnectSocket() -> () {
        let socketStatus : NSStreamStatus = outputStream!.streamStatus
        switch socketStatus {
        case .Open:
            inputStream!.close()
            outputStream!.close()
            print("Sockets closed")
        default:
            break
        }
    }
    
    func openMQTTSocket() -> () {
        print("Socket Status: \(self.connectSocket(self.host as String, port: self.port))")
    }
    
    private func reopenMQTTSocket() -> () {
        print("Socket Reconnected : \(self.connectSocket(self.host as String, port: self.port))")
    }
    
    func disconnectMQTTSocket() -> (){
        self.disconnectSocket()
        self.endKeepAliveTimer()
    }
    
    func connect() -> () {
        self.startKeepAliveTimer()
        print("Socket connected to \(self.host) at \(self.port), sending MQTTConnected")
        let frame : uMQTTConnectFrame = uMQTTConnectFrame()
        let bytesToWire = frame.buildFrame()
        self.outputStream!.write(bytesToWire, maxLength: bytesToWire.count)
    }
    
    func disconnect() -> () {
        let frame : uMQTTDisconnectFrame = uMQTTDisconnectFrame()
        let bytesToWire = frame.buildFrame()
        self.outputStream!.write(bytesToWire, maxLength: bytesToWire.count)
    }
    
    func subscribe(topic: String) -> () {
        let frame : uMQTTSubscribeFrame = uMQTTSubscribeFrame(topic: topic)
        let bytesToWire = frame.buildFrame()
        self.outputStream!.write(bytesToWire, maxLength: bytesToWire.count)
    }
    
    func unsubscribe(topic: String) -> () {
        let frame : uMQTTUnsubscribeFrame = uMQTTUnsubscribeFrame(topic: topic)
        let bytesToWire = frame.buildFrame()
        self.outputStream!.write(bytesToWire, maxLength: bytesToWire.count)
        
    }
    
    func publish(topic: String, payload: String, qos: UInt8 = 0, ret: Bool = false) -> () {
        let frame : uMQTTPublishFrame = uMQTTPublishFrame(topic: topic, payload: payload, dup: false, qos: qos, ret: ret)
        let bytesToWire = frame.buildFrame()
        self.outputStream!.write(bytesToWire, maxLength: bytesToWire.count)
    }
    
    func puback(packetIdentifier: UInt16) -> (){
        let frame : uMQTTPUBACKFrame = uMQTTPUBACKFrame(packetIdentifier: packetIdentifier)
        let bytesToWire = frame.buildFrame()
        self.outputStream!.write(bytesToWire, maxLength: bytesToWire.count)
    }
    
    func ping() -> () {
        let frame : uMQTTPing = uMQTTPing()
        let bytesToWire = frame.buildFrame()
        self.outputStream!.write(UnsafePointer(bytesToWire), maxLength: bytesToWire.count)
    }
    
    private func unwrapPayload(frame:[UInt8]) -> () {
        switch client.currentFrame {
        case .CONNACK:
            switch frame[1] {
            case CONNACKReturnCode.ACCEPTED.rawValue:
                print("Connection Accepted!")
            case CONNACKReturnCode.WRONG_PROTOCOL.rawValue:
                print("Connection Refused, Wrong Protocol Version")
            case CONNACKReturnCode.ID_REJECTED.rawValue:
                print("Connection Refused, Client ID Rejected")
            case CONNACKReturnCode.SERVER_UNAVAILABLE.rawValue:
                print("Connection Refused, Server Unavailable")
            case CONNACKReturnCode.BAD_CREDENTIALS.rawValue:
                print("Connection Refused, Bad Credentials")
            case CONNACKReturnCode.NOT_AUTHORIZED.rawValue:
                print("Connection Refused, Not Authorized")
            default:
                print("Payload not recognized")
            }
        case .SUBACK:
            switch frame[3] {
            case SUBACKReturnCode.MAXQoS0.rawValue:
                print("Success - Maximum QoS 0")
            case SUBACKReturnCode.MAXQoS1.rawValue:
                print("Success - Maximum QoS 1")
            case SUBACKReturnCode.MAXQoS2.rawValue:
                print("Success - Maximum QoS 2")
            case SUBACKReturnCode.Failure.rawValue:
                print("Failure")
            default:
                print("Payload not recognized")
            }
            print("-- Packet Identifier -- \(frame[0]) \(frame[1])")
        case .PUBLISH:
            let dup = (client.currentFrameFlags & 0b00001000) >> 3
            let qos = (client.currentFrameFlags & 0b00000110) >> 1
            let ret = (client.currentFrameFlags & 0b00000001)
            
            let len = (Int)(frame[1] | frame[0] << 4)
            var packetIdentifier : UInt16 = 0
            let payload_len = (Int)(client.currentRemainingLength)
            var startIndex = 2
            let topic : String = String(bytes: frame[startIndex..<(startIndex+len)], encoding: NSUTF8StringEncoding)!
            if qos != 0b00000000 {
                 packetIdentifier = ((UInt16)(frame[(startIndex+len)]) << 8) | (UInt16)(frame[(startIndex+len)+1] & 0b0000000011111111)
                startIndex = (startIndex+len)+2
            }else{
                startIndex = (startIndex+len)
            }
            
            let payload : String = String(bytes: frame[startIndex..<payload_len], encoding:NSUTF8StringEncoding)!
            
            print("PUBLISH TOPIC = \(topic) with Length = \(len)")
            print("PACKET ID = \(packetIdentifier)")
            print("PAYLOAD = \(payload)")
            print("DUP = \(dup)")
            print("RET = \(ret)")
            
            self.delegate!.didReceivedMessage(payload, type: .PUBLISH)
            
            switch qos {
            case QOS.QOS0.rawValue:
                print("None")
            case QOS.QOS1.rawValue:
                print("Send a PUBACK Packet with packetID = \(packetIdentifier)")
                self.puback(packetIdentifier)
            case QOS.QOS2.rawValue:
                print("Send a PUBREC Packet")
            default:
                break
            }
            
        case .UNSUBACK:
            let packetIdentifier = ((UInt16)(frame[0]) << 8) | (UInt16)(frame[1] & 0b0000000011111111)
            print("PACKET ID = \(packetIdentifier)")
        default:
            break;
        }
        
        readBufferLength = 1
        self.client.status = .UNPACK_HEADER
    }
    
    private func unwrapFrame(frame:UInt8) -> () {
        switch client.status {
        case .UNPACK_HEADER:
            switch (frame & 0b11110000) {
            case uMQTTControlFrameType.CONNACK.rawValue:
                print("CONNACK Received")
                client.currentFrame = .CONNACK
            case uMQTTControlFrameType.PINGRESP.rawValue:
                print("PINGRESP Received")
                client.currentFrame = .PINGRESP
            case uMQTTControlFrameType.SUBACK.rawValue:
                print("SUBACK Received")
                client.currentFrame = .SUBACK
            case uMQTTControlFrameType.PUBLISH.rawValue:
                print("PUBLISH Received")
                client.currentFrame = .PUBLISH
            case uMQTTControlFrameType.UNSUBACK.rawValue:
                print("UNSUBACK Received")
                client.currentFrame = .UNSUBACK
            default:
                print("Unkown Header")
            }
            client.currentFrameFlags = frame & 0b00001111
            client.status = .UNPACK_LENGTH
        case .UNPACK_LENGTH:
            print("Lenght = \(frame)")
            client.currentRemainingLength = frame
            readBufferLength = (Int)(frame)
            if(readBufferLength == 0){
                readBufferLength = 1
                client.status = .UNPACK_HEADER
            }else{
                client.status = .UNPACK_VHEADER_PAYLOAD
            }
        case .UNPACK_VHEADER_PAYLOAD:
            break
        }
    }
    
    func connackReceived(frame: UInt8) -> () {
        
    }
    
    func pingrespReceived() -> () {
        print("PINGRESP Received")
    }
    
    func disconnectReceived(){
        print("DISCONNECT Received")
    }
    
    private func startKeepAliveTimer() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = NSTimer.scheduledTimerWithTimeInterval(
            Double(keepAliveInterval) / 2.0,
            target: self,
            selector: #selector(self.ping),
            userInfo: nil,
            repeats: true)
    }
    
    private func endKeepAliveTimer() {
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
        var remainingLength = (UInt8)(self.variableHeader.count + self.payload.count)
        var encodedRemainingLength : [UInt8] = []
        repeat {
            byte = remainingLength % 128
            remainingLength = remainingLength / 128
            if( remainingLength > 0){
                byte = byte | 128
            }
            encodedRemainingLength.append(byte)
        } while( remainingLength > 0 )
        return encodedRemainingLength
    }
    
    private func generatePacketId() -> UInt16 {
        self.packetId += 1
        let nextId = self.packetId
        if (nextId >= UInt16.max) { self.packetId = 1 }
        return nextId
    }
    
    
}

private class uMQTTPing : uMQTTFrame {
    init() {
        super.init(controlFrameType: uMQTTControlFrameType.PINGREQ)
    }
}

private class uMQTTConnectFrame : uMQTTFrame {
    
    let MQTT : String = "MQTT"
    let clientId : String = NSUUID().UUIDString
    var clientUsername : String = ""
    var clientPassword : String = ""
    let clientTopic : String = "a/b"
    let clientMessage : String = "Disconnect"
    let clientKeepAlive : UInt16 = 60
    
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
    
    init(username:String = "", password: String = ""){
        super.init(controlFrameType: uMQTTControlFrameType.CONNECT)
        self.clientUsername = username
        self.clientPassword = password
        self.buildVariableHeader()
        self.buildFlags(false, password: false, willRetain: false, willQoS: 0b00000001, will: true, cleanSession: false)
        self.buildKeepAlive()
        self.buildPayload()
    }
    
    override func buildVariableHeader() -> () {
        self.variableHeader += MQTT.twoBytesLength
        self.variableHeader.append(0b00000100) // Protocol Label Byte
    }
    
    func buildFlags(username: Bool, password: Bool, willRetain: Bool, willQoS: UInt8, will: Bool, cleanSession:Bool) -> () {
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
        self.payload += clientId.twoBytesLength
        self.payload += clientTopic.twoBytesLength
        self.payload += clientMessage.twoBytesLength
        if (self.username) {self.payload += clientUsername.twoBytesLength}
        if (self.password) {self.payload += clientPassword.twoBytesLength}
    }
}

private class uMQTTSubscribeFrame: uMQTTFrame {

    var requestedQoS : UInt8 = 0b0000001
    
    init(topic: String){
        super.init(controlFrameType: uMQTTControlFrameType.SUBSCRIBE, flags:0b00000010)
        self.packetId = self.generatePacketId()
        self.buildVariableHeader()
        self.buildPayload(topic)
    }

    override func buildVariableHeader() {
        self.variableHeader += self.packetId.highestLowest
    }
    
    func buildPayload(topic: String) {
        super.buildPayload()
        self.payload += topic.twoBytesLength
        self.payload.append(requestedQoS)
    }
    
}

private class uMQTTUnsubscribeFrame: uMQTTFrame {
    init(topic: String){
        super.init(controlFrameType: uMQTTControlFrameType.UNSUBSCRIBE, flags:0b00000010)
        self.buildVariableHeader()
        self.buildPayload(topic)
    }
    
    override func buildVariableHeader() {
        self.packetId = self.generatePacketId()
        super.variableHeader += self.packetId.highestLowest
    }
    
    func buildPayload(topic: String) {
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
        super.init(controlFrameType:.PUBLISH)
        self.buildFlags(dup, qos: qos, ret: ret)
        self.buildVariableHeader(topic)
        self.buildPayload(payload)
    }
    
    func buildFlags(dup:Bool, qos:UInt8, ret:Bool) -> (){
        self.dup = dup
        self.qos = qos
        self.ret = ret
        self.fixedHeader |= controlPacketFlags
    }
    
    func buildVariableHeader(topic:String) {
        self.variableHeader += topic.twoBytesLength
        if(qos != 0b00000000){
            self.variableHeader += generatePacketId().highestLowest
        }
    }
    
    func buildPayload(payload:String) {
        self.payload += payload.bytes
    }
}

private class uMQTTPUBACKFrame: uMQTTFrame {

    init(packetIdentifier: UInt16){
        super.init(controlFrameType: uMQTTControlFrameType.PUBACK)
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
        super.init(controlFrameType: uMQTTControlFrameType.PUBREC)
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
        super.init(controlFrameType: uMQTTControlFrameType.DISCONNECT)
        self.buildVariableHeader()
        self.buildPayload()
    }
}
