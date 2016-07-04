//
//  ViewController.swift
//  uMQTTClientApp
//
//  Created by Victor Casé on 6/3/16.
//  Copyright © 2016 Victor Casé. All rights reserved.
//

import UIKit

class ViewController: UIViewController, uMQTTDelegate {
    
    let mqtt : uMQTT = uMQTT(host: "85.119.83.194", atPort: 1883)
    
    @IBOutlet weak var payloadLabel: UILabel!
    @IBOutlet weak var sentBufferLabel: UILabel!
    @IBOutlet weak var connectionStatusLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        mqtt.delegate = self
        mqtt.connect()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    @IBAction func subscribe() {
        mqtt.subscribe("a/b")
    }
    
    @IBAction func unsubscribe() {
        mqtt.unsubscribe("a/b")
    }
    
    @IBAction func publish() {
        mqtt.publish("a/b", payload: "uMQTT works")
    }
    
    @IBAction func connect() {
        mqtt.connect()
    }
    
    @IBAction func disconnect() {
        mqtt.disconnectMQTTSocket();
    }
    
    func didConnectedWithSuccess(message: String) {
        dispatch_async(dispatch_get_main_queue(), {
            self.connectionStatusLabel.text = message
        })
    }
    
    func didConnectedWithError(message: String) {
        dispatch_async(dispatch_get_main_queue(), {
            self.connectionStatusLabel.text = message
        })
    }

    func readyToSendMessage() {
        print("Ready to Work")
    }
    
    func didSendMessage(message: String) {
        print("\(message)")
    }
    
    func didReceivedMessage(message: String, type:uMQTTControlFrameType) {
        dispatch_async(dispatch_get_main_queue(), {
            self.payloadLabel.text = message
            self.resetBufferLabel()
        })
    }
    
    func resetBufferLabel() -> () {
        let delay = 1.5 * Double(NSEC_PER_SEC)
        let dispatchTime = dispatch_time(DISPATCH_TIME_NOW, Int64(delay))
        dispatch_after(dispatchTime, dispatch_get_main_queue(), {
            self.payloadLabel.text = "Payload"
        })
    }
}

