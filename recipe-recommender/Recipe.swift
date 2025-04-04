
import Foundation
// Update the Recipe struct to include preference
struct Recipe {
    let title: String
    let detectedIngredients: [String]
    let recipeIngredients: [String]
    let instructions: [String]
    let prepTime: String
    let cookTime: String
    let servings: Int
    let difficulty: String
    let cuisine: String
    let imageURL: URL?
    let description: String
    let nutritionFacts: NutritionFacts?
    let dietaryRestrictions: Set<DietaryRestriction>
    let preference: RecipePreference? // Add this
    
    // Add this initializer with preference parameter
    init(title: String, detectedIngredients: [String], recipeIngredients: [String], instructions: [String], prepTime: String, cookTime: String, servings: Int, difficulty: String, cuisine: String, imageURL: URL? = nil, description: String, nutritionFacts: NutritionFacts? = nil, dietaryRestrictions: Set<DietaryRestriction> = [], preference: RecipePreference? = nil) {
        self.title = title
        self.detectedIngredients = detectedIngredients
        self.recipeIngredients = recipeIngredients
        self.instructions = instructions
        self.prepTime = prepTime
        self.cookTime = cookTime
        self.servings = servings
        self.difficulty = difficulty
        self.cuisine = cuisine
        self.imageURL = imageURL
        self.description = description
        self.nutritionFacts = nutritionFacts
        self.dietaryRestrictions = dietaryRestrictions
        self.preference = preference
    }
}


struct NutritionFacts {
    let calories: Int
    let protein: Int // grams
    let carbs: Int   // grams
    let fat: Int     // grams
}
