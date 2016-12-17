# uMQTT
An µ MQTT Client Library written in Swift easy to integrate and without external dependencies :)

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
        self.umqtt = uMQTT(host: "x.x.x.x", atPort: 1883)
        umqtt.delegate = self
    }
    
    func start(){
        print("uMQTT connection pool will start!")
        umqtt.connect()
    }
    
    func restart(){
        print("uMQTT connection pool will restart")
        self.umqtt = uMQTT(host: "x.x.x.x"), atPort:1883)
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

#Broker List
* https://github.com/emqtt/emqttd
* https://github.com/eclipse/mosquitto





