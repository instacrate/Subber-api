//
//  ShippingController.swift
//  subber-api
//
//  Created by Hakon Hanesand on 10/1/16.
//
//

import Foundation
import Vapor
import HTTP
import Routing
import JSON
import Node
import Fluent

extension Collection where Iterator.Element == Int, IndexDistance == Int {
    
    var total: Iterator.Element {
        return reduce(0, +)
    }
    
    var average: Double {
        return isEmpty ? 0 : Double(total) / Double(count)
    }
}

fileprivate func createShortNode(box: Box, vendor: Vendor, reviews: [Review], picture: Picture) throws -> Node {
    return try Node(node : [
        "name" : .string(box.name),
        "short_desc" : .string(box.short_desc),
        "vendor_name" : .string(vendor.name),
        "price" : .number(.double(box.price)),
        "picture" : .string(picture.url),
        "averageRating" : .number(.double(reviews.map { $0.rating }.average))
    ])
}

fileprivate func createExtensiveNode(box: Box, vendor: Vendor, reviews: [Review], pictures: [Picture]) throws -> Node {
    return try Node(node : [
        "box" : box.makeNode(),
        "vendor" : vendor.makeNode(),
        "reviews" : .array(reviews.map { try $0.makeNode() }),
        "pictures" : .array(pictures.map { try $0.makeNode() })
        ])
}

final class BoxCollection : RouteCollection, EmptyInitializable {
    
    init () {}
    
    typealias Wrapped = HTTP.Responder
    
    func build<Builder : RouteBuilder>(_ builder: Builder) where Builder.Value == Responder {
        
        builder.group("box") { box in
            
            box.get("short", Box.self) { request, box in
                
                let (vendor, reviews, pictures) = try box.gatherRelations()
                
                guard let picture = pictures.first else {
                    throw Abort.custom(status: .internalServerError, message: "Box has no pictures.")
                }
                
                return try JSON(node: createShortNode(box: box, vendor: vendor, reviews: reviews, picture: picture))
            }
            
            box.get(Box.self) { request, box in
                let (vendor, reviews, pictures) = try box.gatherRelations()
                
                return try JSON(createExtensiveNode(box: box, vendor: vendor, reviews: reviews, pictures: pictures))
            }
            
            box.get("category", Category.self) { request, category in
                let boxes = try category.boxes().all()
                
                // TODO : Make concurrent
                // TODO : Optimize queries based on information needed
                
                return try JSON(node: .array(boxes.map { box in
                    let (vendor, reviews, pictures) = try box.gatherRelations()
                    
                    guard let picture = pictures.first else {
                        throw Abort.custom(status: .internalServerError, message: "Box has no pictures.")
                    }
                    
                    return try createShortNode(box: box, vendor: vendor, reviews: reviews, picture: picture)
                }))
            }
            
            box.get("featured") { request in
                return try FeaturedBox.all().makeJSON()
            }
            
            box.get("new") { request in
                
                Droplet.instance?.console.info(request.description)
                Droplet.instance?.console.info(Calendar.current.description)
                Droplet.instance?.console.info(Date().description)
                
                let dateComponents = DateComponents(day: -14)
                
                if let s = Calendar.current.date(byAdding: dateComponents, to: Date()) {
                    Droplet.instance?.console.info(s.description)
                }
                
                guard let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -2 * 7, to: Date()) else {
                    throw Abort.custom(status: .internalServerError, message: "Error calculating date")
                }
                
                let query = try Box.query().filter("publish_date", .greaterThan, oneWeekAgo.timeIntervalSince1970)
                let boxes = try query.all()
                
                return try JSON(node: .array(boxes.map { box in
                    let (vendor, reviews, pictures) = try box.gatherRelations()
                    
                    guard let picture = pictures.first else {
                        throw Abort.custom(status: .internalServerError, message: "Box has no pictures.")
                    }
                    
                    return try createShortNode(box: box, vendor: vendor, reviews: reviews, picture: picture)
                }))
            }
            
            box.get() { request in
                
                guard let ids = request.query?["id"]?.array?.flatMap({ $0.string }) else {
                    throw Abort.custom(status: .badRequest, message: "Expected query parameter with name id.")
                }
                
                let boxes = try Box.query().filter("id", .in, ids).all()
                
                return try JSON(node: .array(boxes.map { box in
                    let (vendor, reviews, pictures) = try box.gatherRelations()
                    
                    guard let picture = pictures.first else {
                        throw Abort.custom(status: .internalServerError, message: "Box has no pictures.")
                    }
                    
                    return try createShortNode(box: box, vendor: vendor, reviews: reviews, picture: picture)
                }))
            }
            
            box.post("create") { request in
                
                guard let json = request.json else {
                    throw Abort.badRequest
                }
                
                guard var box = try? Box(json: json) else {
                    throw Abort.badRequest
                }
                
                try box.save()
                
                return try box.makeJSON()
            }
        }
    }
}
