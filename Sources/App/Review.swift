//
//  Review.swift
//  subber-api
//
//  Created by Hakon Hanesand on 9/27/16.
//
//

import Vapor
import Fluent
import Foundation

final class Review: Model, Preparation, JSONConvertible, FastInitializable {
    
    static var requiredJSONFields = ["text", "rating", "date", "box_id", "customer_id"]
    
    var id: Node?
    var exists = false
    
    let text: String
    let rating: Int
    let date: Date
    
    var box_id: Node?
    var customer_id: Node?
    
    init(node: Node, in context: Context) throws {
        id = try? node.extract("id")
        text = try node.extract("text")
        rating = try node.extract("rating")
        date = (try? node.extract("date")) ?? Date()
        box_id = try node.extract("box_id")
        customer_id = try node.extract("customer_id")
    }
    
    func makeNode(context: Context) throws -> Node {
        return try Node(node: [
            "text" : .string(text),
            "rating" : .number(.int(rating)),
            "date" : .string(date.ISO8601String),
            "box_id" : box_id!,
            "customer_id" : customer_id!
        ]).add(name: "id", node: id)
    }
    
    static func prepare(_ database: Database) throws {
        try database.create(self.entity, closure: { box in
            box.id()
            box.string("text")
            box.string("rating")
            box.string("date")
            box.parent(Box.self, optional: false)
            box.parent(Customer.self, optional: false)
        })
    }
    
    static func revert(_ database: Database) throws {
        try database.delete(self.entity)
    }
}

extension Review {
    
    func box() throws -> Parent<Box> {
        return try parent(box_id)
    }
    
    func user() throws -> Parent<Customer> {
        return try parent(customer_id)
    }
}

extension Review: Relationable {
    
    typealias Relations = (user: Customer, box: Box)

    func relations() throws -> (user: Customer, box: Box) {
        guard let user = try self.user().get() else {
            throw Abort.custom(status: .internalServerError, message: "Missing user relation for review with text \(text)")
        }
        
        guard let box = try self.box().get() else {
            throw Abort.custom(status: .internalServerError, message: "Missing box relation for review with text \(text)")
        }
        
        return (user, box)
    }
}
