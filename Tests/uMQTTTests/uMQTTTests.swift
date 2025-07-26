import XCTest
@testable import uMQTT

final class uMQTTTests: XCTestCase {
    private func mqttWithMemoryStream() -> uMQTT {
        let mqtt = uMQTT(host: "localhost", autoconnect: false)
        mqtt.inputStream = InputStream(data: Data())
        mqtt.outputStream = OutputStream.toMemory()
        mqtt.outputStream.open()
        return mqtt
    }

    private func writtenBytes(from stream: OutputStream) -> [UInt8] {
        stream.close()
        let data = stream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data
        return Array(data ?? Data())
    }

    func testConnectWritesConnectFrame() {
        let mqtt = mqttWithMemoryStream()
        mqtt.connect()
        let bytes = writtenBytes(from: mqtt.outputStream)
        XCTAssertEqual(bytes.first, uMQTTControlFrameType.connect.rawValue)
    }

    func testDisconnectWritesDisconnectFrame() {
        let mqtt = mqttWithMemoryStream()
        mqtt.disconnect()
        let bytes = writtenBytes(from: mqtt.outputStream)
        XCTAssertEqual(bytes.first, uMQTTControlFrameType.disconnect.rawValue)
    }

    func testSubscribeWritesSubscribeFrame() {
        let mqtt = mqttWithMemoryStream()
        mqtt.subscribe("test/topic")
        let bytes = writtenBytes(from: mqtt.outputStream)
        XCTAssertEqual(bytes.first, uMQTTControlFrameType.subscribe.rawValue | 0b00000010)
    }

    func testUnsubscribeWritesUnsubscribeFrame() {
        let mqtt = mqttWithMemoryStream()
        mqtt.unsubscribe("test/topic")
        let bytes = writtenBytes(from: mqtt.outputStream)
        XCTAssertEqual(bytes.first, uMQTTControlFrameType.unsubscribe.rawValue | 0b00000010)
    }

    func testPublishWritesPublishFrame() {
        let mqtt = mqttWithMemoryStream()
        mqtt.publish("test/topic", payload: "hello")
        // allow async queue to finish
        let expectation = XCTestExpectation(description: "publish")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
        let bytes = writtenBytes(from: mqtt.outputStream)
        XCTAssertEqual(bytes.first, uMQTTControlFrameType.publish.rawValue)
    }

    func testPingWritesPingFrame() {
        let mqtt = mqttWithMemoryStream()
        mqtt.ping()
        let bytes = writtenBytes(from: mqtt.outputStream)
        XCTAssertEqual(bytes.first, uMQTTControlFrameType.pingreq.rawValue)
    }
}
