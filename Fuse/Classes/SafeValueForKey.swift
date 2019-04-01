import Foundation

func safeValue(forKey key: String, from instance: Any) -> Any? {
    let copy = Mirror(reflecting: instance)
    for child in copy.children.makeIterator() {
        if let label = child.label, label == key {
            return child.value
        }
    }
    
    return nil
}
