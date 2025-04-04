import SwiftUI

struct AppTheme {
    // Color palette
    static let terracotta = Color(red: 224/255, green: 122/255, blue: 95/255)
    static let sageGreen = Color(red: 129/255, green: 178/255, blue: 154/255)
    static let butterYellow = Color(red: 242/255, green: 204/255, blue: 143/255)
    static let softCream = Color(red: 247/255, green: 243/255, blue: 227/255)
    static let deepCharcoal = Color(red: 61/255, green: 64/255, blue: 91/255)
    
    // Common gradients
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [softCream, butterYellow.opacity(0.3)]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
