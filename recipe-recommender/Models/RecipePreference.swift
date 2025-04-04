enum RecipePreference: String, CaseIterable, Identifiable {
    case sweet = "Sweet"
    case savory = "Savory"
    case baked = "Baked"
    case grilled = "Grilled"
    case fried = "Fried"
    case healthy = "Healthy"
    case quick = "Quick & Easy"
    case gourmet = "Gourmet"
    
    var id: String { self.rawValue }
    
    var description: String {
        switch self {
        case .sweet: return "Desserts, cakes, cookies, and sweet treats"
        case .savory: return "Savory and hearty meals"
        case .baked: return "Anything baked in the oven"
        case .grilled: return "Grilled food and BBQ"
        case .fried: return "Pan-fried or deep-fried dishes"
        case .healthy: return "Nutritious and balanced meals"
        case .quick: return "Ready in 30 minutes or less"
        case .gourmet: return "Fancy restaurant-style cooking"
        }
    }
    
    var icon: String {
        switch self {
        case .sweet: return "birthday.cake"
        case .savory: return "fork.knife"
        case .baked: return "oven"
        case .grilled: return "flame"
        case .fried: return "frying.pan"
        case .healthy: return "leaf"
        case .quick: return "timer"
        case .gourmet: return "star"
        }
    }
}
