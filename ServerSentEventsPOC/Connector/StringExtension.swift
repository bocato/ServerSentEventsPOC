//
//  StringExtension.swift
//  ServerSentEventsPOC
//
//  Created by Eduardo Sanches Bocato on 24/09/18.
//  Copyright © 2018 Bocato. All rights reserved.
//

import Foundation

extension String {
    
    func toDictionary() -> [String: AnyObject]? {
        if let data = self.data(using: String.Encoding.utf8) {
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: AnyObject]
                return json
            }
            catch {
                debugPrint(error)
            }
        }
        
        return nil
    }
    
}
