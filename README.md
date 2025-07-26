# uMQTT
An µ MQTT Client Library written in Swift. It is easy to integrate and has no external
dependencies. You can now also integrate it using the Swift Package Manager.

# What is MQTT

_MQTT is a machine-to-machine (M2M)/"Internet of Things" connectivity protocol. It was designed as an extremely lightweight publish/subscribe messaging transport. It is useful for connections with remote locations where a small code footprint is required and/or network bandwidth is at a premium._

* http://mqtt.org/
* http://www.hivemq.com/blog/mqtt-essentials-wrap-up

# How to Use

You can start a MQTT Message Poll at your AppDelegate implementation

```
  func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
    MessagePollManager.sharedInstance.start()
    return true
}
```

You can wrap the uMQTT into your custom class, here a simple example of how you can do it.
```
  class MessagePollManager: uMQTTDelegate {
      static let sharedInstance = MessagePollManager()
      private var umqtt : uMQTT

      private init(){
        // autoconnect can be disabled for unit tests
        self.umqtt = uMQTT(host: "x.x.x.x", atPort: 1883)
        umqtt.delegate = self
    }
    
    func start(){
        print("uMQTT connection pool will start!")
        umqtt.connect()
    }
    
    func restart(){
        print("uMQTT connection pool will restart")
        self.umqtt = uMQTT(host: "x.x.x.x", atPort: 1883)
        umqtt.delegate = self
        self.start()
    }
    
    func stop(){
        print("uMQTT connection pool will stop")
        umqtt.disconnect()
        umqtt.disconnectSocket()
    }
    
    func subscribeWithTopic(topic:String){
        umqtt.subscribe(topic)
    }
    
    func unsubscribeFromTopic(topic:String){
        umqtt.unsubscribe(topic)
    }
    
    func publish(topic:String, message:String){
        umqtt.publish(topic, payload: message, qos: 0b00000001)
    }
```

The initializer automatically establishes the network connection. If you need to control when the socket is opened (for example in unit tests), pass `autoconnect: false`.

#Broker List
* https://github.com/emqtt/emqttd
* https://github.com/eclipse/mosquitto


## Swift Package Manager

Add `uMQTT` as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/uMQTT.git", from: "1.0.0")
]

targets: [
    .target(
        name: "YourApp",
        dependencies: ["uMQTT"])
]
```

Then import `uMQTT` in your Swift sources.





