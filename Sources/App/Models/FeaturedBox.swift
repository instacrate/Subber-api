//
//  FeaturedBox.swift
//  subber-api
//
//  Created by Hakon Hanesand on 10/12/16.
//
//

import Vapor
import Fluent
import Foundation

final class FeaturedBox: Model, Preparation, JSONConvertible {
    
    public static var entity = "featured_boxes"
    var exists = false
    
    var id: Node?
    var type: Box.Curated
    var box_id: Node?
    
    init(node: Node, in context: Context) throws {
        id = try node.extract("id")
        type = try node.extract("type")
        box_id = try node.extract("box_id")
    }
    
    func makeNode(context: Context) throws -> Node {
        return try Node(node: [
            "box_id" : box_id!,
            "type" : .string(type.rawValue)
        ]).add(name: "id", node: id)
    }
    
    static func prepare(_ database: Database) throws {
        try database.create(self.entity, closure: { box in
            box.id()
            box.parent(Box.self, optional: false)
            box.string("type")
        })
    }
    
    static func revert(_ database: Database) throws {
        try database.delete(self.entity)
    }
}

extension FeaturedBox {
    
    func box() throws -> Parent<Box> {
        return try parent(box_id)
    }
}
