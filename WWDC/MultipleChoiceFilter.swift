//
//  MultipleChoiceFilter.swift
//  WWDC
//
//  Created by Guilherme Rambo on 27/05/17.
//  Copyright © 2017 Guilherme Rambo. All rights reserved.
//

import Foundation

struct FilterOption: Equatable {
    let title: String
    let value: String
    
    static func ==(lhs: FilterOption, rhs: FilterOption) -> Bool {
        return lhs.value == rhs.value
    }
}

struct MultipleChoiceFilter: FilterType {
    
    var identifier: String
    var isSubquery: Bool
    var collectionKey: String
    var modelKey: String
    var options: [FilterOption]
    var selectedOptions: [FilterOption]
    
    var emptyTitle: String
    
    
    var isEmpty: Bool {
        return selectedOptions.isEmpty
    }
    
    var title: String {
        if isEmpty || selectedOptions.count == options.count {
            return emptyTitle
        } else {
            let t = selectedOptions.reduce("", { $0 + ", " + $1.title })
            
            guard !t.isEmpty else { return t }
            
            return t.substring(from: t.index(t.startIndex, offsetBy: 2))
        }
    }
    
    var predicate: NSPredicate? {
        guard !isEmpty else { return nil }
        
        let subpredicates = selectedOptions.map { option -> NSPredicate in
            let format: String
            
            if isSubquery {
                format = "SUBQUERY(\(collectionKey), $\(collectionKey), $\(collectionKey).\(modelKey) == %@).@count > 0"
            } else {
                format = "\(modelKey) == %@"
            }
            
            return NSPredicate(format: format, option.value)
        }
        
        return NSCompoundPredicate(orPredicateWithSubpredicates: subpredicates)
    }
    
}
