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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        mqtt.delegate = self
        mqtt.openMQTTSocket()
        mqtt.connect()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    @IBAction func subscribe() {
        mqtt.subscribe("a/b")
    }
    
    @IBAction func disconnect() {
        mqtt.disconnectMQTTSocket();
    }
    
    func readyToSendMessage() {
        print("Ready to Work")
    }
    
    func didReceivedMessage() {
        print("Message Arrived")
    }
}

