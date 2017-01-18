//
//  Entity+Relation.swift
//  subber-api
//
//  Created by Hakon Hanesand on 9/28/16.
//
//

import Fluent
import Vapor

enum Format {
    case short
    case long
    
    func optimize<T : Model>(query: Query<T>) {
        switch self {
            
        case .short:
            
            switch T.self {
                
            case is Picture.Type:
                query.limit = Limit(count: 1)
                
            default: break
                
            }
            
        default: break
        }
    }
}

extension Array where Element : NodeRepresentable {
    
    public func makeJSON() throws -> JSON {
        let node = try Node.array(self.map { try $0.makeNode() })
        return try JSON(node: node)
    }
}

extension Array where Element : NodeInitializable {
    
    public init(json: JSON) throws {
        let node = json.makeNode()
        try self.init(node: node)
    }
}
