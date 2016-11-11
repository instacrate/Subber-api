//
//  OrderCollection.swift
//  subber-api
//
//  Created by Hakon Hanesand on 10/10/16.
//
//


import Foundation
import Vapor
import HTTP
import Routing
import JSON
import Auth

final class Stripe {
    
    typealias Token = String
    
    static func createStripeCustomer(forUser user: inout Customer, withPaymentSource source: Token) throws -> Token {
        
        let authString = "sk_test_6zSrUMIQfOCUorVvFMS2LEzn:".data(using: .utf8)!.base64EncodedString()
        let response = try drop.client.post("https://api.stripe.com/v1/customers", headers: ["Authorization" : "Basic \(authString)"], query: ["source" : source])
        
        guard let json = try? response.json() else {
            throw Abort.custom(status: .internalServerError, message: response.description)
        }
        
        guard let customer_id = json["id"]?.string else {
            throw Abort.custom(status: .internalServerError, message: response.description)
        }
        
        user.stripe_id = customer_id
        try user.save()
        
        return customer_id
    }
    
    static func associate(paymentSource source: Token, withUser user: Customer) throws -> Token {
        
        precondition(user.stripe_id != nil, "User must have a stripe id.")
        
        let authString = "sk_test_6zSrUMIQfOCUorVvFMS2LEzn:".data(using: .utf8)!.base64EncodedString()
        let response = try drop.client.post("https://api.stripe.com/v1/customers/\(user.stripe_id!)/sources", headers: ["Authorization" : "Basic \(authString)"], query: ["source" : source])
        
        guard let json = try? response.json() else {
            throw Abort.custom(status: .internalServerError, message: response.description)
        }
        
        guard let card_id = json["id"]?.string else {
            throw Abort.custom(status: .internalServerError, message: response.description)
        }
        
        return card_id
    }
    
    static func createPlan(forBox box: inout Box) throws {
        precondition(box.plan_id == nil, "Box already had plan.")
        let planId = UUID().uuidString
        
        let parameters = ["id" : "\(planId)",
                          "amount" : "\(Int(box.price * 100))",
                          "currency" : "usd",
                          "interval" : "month",
                          "name" : box.name]
        
        let authString = "sk_test_6zSrUMIQfOCUorVvFMS2LEzn:".data(using: .utf8)!.base64EncodedString()
        let response = try drop.client.post("https://api.stripe.com/v1/plans", headers: ["Authorization" : "Basic \(authString)"], query: parameters)
        
        guard let json = try? response.json() else {
            throw Abort.custom(status: .internalServerError, message: response.description)
        }
        
        guard json["id"]?.string != nil else {
            throw Abort.custom(status: .internalServerError, message: response.description)
        }
        
        box.plan_id = planId
        try box.save()
    }
    
    static func createSubscription(forUser user: Customer, forBox box: Box, withFrequency frequency: Frequency = .monthly) throws -> String {
        
        precondition(user.stripe_id != nil, "User must have a stripe id.")
        precondition(box.plan_id != nil, "Box must have a plan id.")
        
        let authString = "sk_test_6zSrUMIQfOCUorVvFMS2LEzn:".data(using: .utf8)!.base64EncodedString()
        let response = try drop.client.post("https://api.stripe.com/v1/subscriptions", headers: ["Authorization" : "Basic \(authString)"], query: ["customer" : user.stripe_id!, "plan" : box.plan_id!])
        
        guard let json = try? response.json() else {
            throw Abort.custom(status: .internalServerError, message: response.description)
        }
        
        guard let subscription_id = json["id"]?.string else {
            throw Abort.custom(status: .internalServerError, message: response.description)
        }
        
        if frequency == .once {
            let response = try drop.client.delete("https://api.stripe.com/v1/subscriptions/\(subscription_id)", headers: ["Authorization" : "Basic \(authString)"], query: ["at_period_end" : true])
            
            guard let json = try? response.json() else {
                throw Abort.custom(status: .internalServerError, message: response.description)
            }
            
            guard let test = json["cancel_at_period_end"]?.bool, test else {
                throw Abort.custom(status: .internalServerError, message: response.description)
            }
        }
        
        return subscription_id
    }
    
    static func paymentMethods(forUser user: Customer) throws -> JSON {
        
        let authString = "sk_test_6zSrUMIQfOCUorVvFMS2LEzn:".data(using: .utf8)!.base64EncodedString()
        let response = try drop.client.get("https://api.stripe.com/v1/customers/\(user.stripe_id!)/sources?object=card", headers: ["Authorization" : "Basic \(authString)"])
        
        guard let json = try? response.json() else {
            throw Abort.custom(status: .internalServerError, message: response.description)
        }
        
        guard let cards = try json["data"]?.makeJSON() else {
            throw Abort.custom(status: .internalServerError, message: response.description)
        }
        
        return cards
    }
}

final class OrderCollection : RouteCollection, EmptyInitializable {
    
    init () {}
    
    typealias Wrapped = HTTP.Responder
    
    func build<Builder : RouteBuilder>(_ builder: Builder) where Builder.Value == Responder {
        
        builder.grouped(Droplet.protect(.user)).group("order") { order in
            
            order.group("customer") { customer in
                
                customer.post("add", String.self) { request, token in
                    
                    var user = try request.customer()
                    
                    if user.stripe_id != nil {
                        _ = try Stripe.associate(paymentSource: token, withUser: user)
                        return try Response(status: .created, json: JSON(node: []))
                    } else {
                        let id = try Stripe.createStripeCustomer(forUser: &user, withPaymentSource: token)
                        return try Response(status: .created, json: JSON(node: ["id" : id]))
                    }
                }
                
                customer.grouped("subscribe").post(Box.self, Shipping.self, Frequency.self) { request, _box, shipping, frequency in
                    
                    var box = _box
                    
                    if box.plan_id == nil {
                        try Stripe.createPlan(forBox: &box)
                    }
                    
                    precondition(box.plan_id != nil, "Box must have plan id")
                    
                    let user = try request.customer()
                    let subscriptionId = try Stripe.createSubscription(forUser: user, forBox: box, withFrequency: frequency)
                    
                    var subscription = Subscription(withId: subscriptionId, box: box, user: user, shipping: shipping, freq: frequency)
                    try subscription.save()
                    
                    return Response(status: .created)
                }
            }
        }
        
        builder.grouped(Droplet.protect(.user)).group("user") { user in
            
            user.get("shipping") { request in
                return try Node.array(request.customer().shippingAddresses().all().map { try $0.makeNode() })
            }
            
            user.get("payment") { request in
                return try Stripe.paymentMethods(forUser: request.customer())
            }
            
        }
    }
}
