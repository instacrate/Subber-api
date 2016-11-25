//
//  CategoryController.swift
//  subber-api
//
//  Created by Hakon Hanesand on 11/15/16.
//
//

import Foundation
import Vapor
import HTTP

final class CategoryController: ResourceRepresentable {
    
    func show(_ request: Request, category: Category) throws -> ResponseRepresentable {
        return try category.boxes().all().makeJSON()
    }
    
    func create(_ request: Request) throws -> ResponseRepresentable {
        var category = try Category(json: request.json())
        try category.save()
        return try Response(status: .created, json: category.makeJSON())
    }
    
    func makeResource() -> Resource<Category> {
        return Resource(
            store: create,
            show: show
        )
    }
}
