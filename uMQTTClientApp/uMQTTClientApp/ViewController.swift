//
//  ViewController.swift
//  uMQTTClientApp
//
//  Created by Victor Casé on 6/3/16.
//  Copyright © 2016 Victor Casé. All rights reserved.
//

import UIKit

class ViewController: UIViewController, uMQTTDelegate {
    
    let mqtt : uMQTT = uMQTT()
    
    @IBOutlet weak var payloadLabel: UILabel!
    
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
    
    @IBAction func disconnect() {
        mqtt.disconnectMQTTSocket();
    }
    
    
    func readyToSendMessage() {
        print("Ready to Work")
    }
    
    func didSendMessage(message: String) {
        print("\(message)")
    }
    
    func didReceivedMessage(message: String, type:uMQTTControlFrameType) {
        print("Message Arrived")
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

