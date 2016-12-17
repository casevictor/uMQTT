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
        mqtt.disconnectSocket();
    }
    
    func didConnectedWithSuccess(_ message: String) {
        DispatchQueue.main.async(execute: {
            self.connectionStatusLabel.text = message
        })
    }
    
    func didConnectedWithError(_ message: String) {
        DispatchQueue.main.async(execute: {
            self.connectionStatusLabel.text = message
        })
    }
    
    internal func didConnectionErrorOcurred() {
        DispatchQueue.main.async(execute: {
            self.connectionStatusLabel.text = "Error"
        })
    }

    func readyToSendMessage() {
        print("Ready to Work")
    }
    
    func didSendMessage(_ message: String) {
        print("\(message)")
    }
    
    func didReceivedMessage(_ message: String, type:uMQTTControlFrameType) {
        DispatchQueue.main.async(execute: {
            self.payloadLabel.text = message
            self.resetBufferLabel()
        })
    }
    
    func resetBufferLabel() -> () {
        let delay = 1.5 * Double(NSEC_PER_SEC)
        let dispatchTime = DispatchTime.now() + Double(Int64(delay)) / Double(NSEC_PER_SEC)
        DispatchQueue.main.asyncAfter(deadline: dispatchTime, execute: {
            self.payloadLabel.text = "Payload"
        })
    }
}

