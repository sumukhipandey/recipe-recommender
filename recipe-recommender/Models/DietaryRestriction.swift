import Foundation

// Enum for dietary restrictions
enum DietaryRestriction: String, CaseIterable, Identifiable {
    case vegan = "Vegan"
    case vegetarian = "Vegetarian"
    case glutenFree = "Gluten Free"
    case dairyFree = "Dairy Free"
    case nutFree = "Nut Free"
    case kosher = "Kosher"
    case halal = "Halal"
    
    var id: String { self.rawValue }
}