import Foundation
import UIKit
import SwiftUI

class ClaudeAPIClient {
    private let apiKey: String
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let logger = Logger.shared
    
    // Maximum image size to send to Claude API in MB
    private let maxImageSizeMB: Double = 1.0
    
    init(apiKey: String) {
        self.logger.log("Initializing Claude API Client")
        self.apiKey = apiKey
    }
    
    // MARK: - Ingredient Detection from Images
    
    func detectIngredients(from image: UIImage, completion: @escaping (Result<[String], Error>) -> Void) {
        logger.log("Starting ingredient detection from image")
        
        // STEP 1: Initial image info logging
        if let cgImage = image.cgImage {
            logger.log("Original image: \(cgImage.width)x\(cgImage.height), orientation: \(image.imageOrientation.rawValue)", level: .debug)
            if let colorSpace = cgImage.colorSpace {
                logger.log("Color space: \(colorSpace)", level: .debug)
            }
        } else {
            logger.log("Image doesn't have a valid CGImage", level: .warning)
        }
        
        // STEP 2: Downsize large images before processing
        logger.log("Starting initial image downsizing")
        let maxDimension: CGFloat = 1000 // Max 1000px in any dimension
        let downsizedImage = downsizeImage(image, maxDimension: maxDimension)
        
        // STEP 3: Process the image to ensure compatibility
        logger.log("Processing image for API compatibility")
        var processedImage: UIImage
        do {
            guard let processed = try preprocessImage(downsizedImage) else {
                let error = NSError(domain: "ClaudeAPIError", code: 1001,
                                    userInfo: [NSLocalizedDescriptionKey: "Failed to preprocess image"])
                logger.log("Image preprocessing failed", level: .error)
                completion(.failure(error))
                return
            }
            processedImage = processed
            logger.log("Image successfully preprocessed")
        } catch {
            logger.log("Image preprocessing error: \(error.localizedDescription)", level: .error)
            completion(.failure(error))
            return
        }
        
        // STEP 4: Convert to JPEG with compression
        logger.log("Converting image to JPEG with compression")
        var compressionQuality: CGFloat = 0.7
        var imageData: Data
        
        guard let data = processedImage.jpegData(compressionQuality: compressionQuality) else {
            let error = NSError(domain: "ClaudeAPIError", code: 1002,
                                userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to JPEG data"])
            logger.log("JPEG conversion failed", level: .error)
            completion(.failure(error))
            return
        }
        
        // STEP 5: Image size checking and reduction
        imageData = data
        var fileSizeMB = Double(imageData.count) / 1_000_000.0
        logger.log("Image size after initial compression: \(String(format: "%.2f", fileSizeMB)) MB")
        
        // Iteratively reduce quality until under max size
        var compressionAttempt = 1
        while fileSizeMB > maxImageSizeMB && compressionQuality > 0.1 {
            compressionQuality -= 0.1
            logger.log("Compression attempt #\(compressionAttempt): reducing quality to \(String(format: "%.1f", compressionQuality))")
            if let reducedData = processedImage.jpegData(compressionQuality: compressionQuality) {
                imageData = reducedData
                fileSizeMB = Double(imageData.count) / 1_000_000.0
                logger.log("New image size: \(String(format: "%.2f", fileSizeMB)) MB")
            } else {
                logger.log("Failed to create JPEG with reduced quality", level: .warning)
                break
            }
            compressionAttempt += 1
        }
        
        // If still too large after compression, resize further
        if fileSizeMB > maxImageSizeMB {
            logger.log("Image still too large (\(String(format: "%.2f", fileSizeMB)) MB), attempting further resizing", level: .warning)
            if let resizedImage = resizeImage(processedImage, targetSizeMB: maxImageSizeMB) {
                if let resizedData = resizedImage.jpegData(compressionQuality: 0.5) {
                    imageData = resizedData
                    fileSizeMB = Double(imageData.count) / 1_000_000.0
                    logger.log("Final image size after resizing: \(String(format: "%.2f", fileSizeMB)) MB")
                }
            }
        }
        
        // Final size check before sending
        if fileSizeMB > 5.0 {
            logger.log("Image is still very large (\(String(format: "%.2f", fileSizeMB)) MB). This may cause API issues.", level: .warning)
        }
        
        // STEP 6: Send to API
        logger.log("Sending image of size \(String(format: "%.2f", fileSizeMB)) MB to Claude API")
        encodeAndSendImageForAnalysis(imageData, completion: completion)
    }
    
    // Method to downsize large images before preprocessing
    private func downsizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        // Check if the image is larger than maxDimension in either dimension
        let width = image.size.width
        let height = image.size.height
        
        if width <= maxDimension && height <= maxDimension {
            logger.log("Image already within size limits: \(width)x\(height)")
            return image
        }
        
        // Calculate the scale factor to reduce the larger dimension to maxDimension
        let scaleFactor = width > height
            ? maxDimension / width
            : maxDimension / height
        
        let newWidth = width * scaleFactor
        let newHeight = height * scaleFactor
        
        logger.log("Downsizing image from \(width)x\(height) to \(newWidth)x\(newHeight)")
        
        // Create the resized image
        UIGraphicsBeginImageContextWithOptions(CGSize(width: newWidth, height: newHeight), false, 1.0)
        image.draw(in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        
        return resizedImage
    }
    
    // Preprocess the image to ensure it's in a format Claude can handle
    private func preprocessImage(_ image: UIImage) throws -> UIImage? {
        logger.log("Starting image preprocessing")
        
        // Check if image has a valid CGImage
        guard let inputCGImage = image.cgImage else {
            logger.log("Error: Input image doesn't have a valid CGImage", level: .error)
            throw NSError(domain: "ImageProcessingError", code: 1001,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid input image - no CGImage"])
        }
        
        // Use the device RGB color space which is safe
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            logger.log("Error: Couldn't create sRGB color space", level: .error)
            throw NSError(domain: "ImageProcessingError", code: 1002,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create color space"])
        }
        
        // Create a new context with standard parameters
        let width = inputCGImage.width
        let height = inputCGImage.height
        let bitsPerComponent = 8
        let bytesPerRow = width * 4 // 4 bytes per pixel (RGBA)
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        
        logger.log("Creating context with dimensions: \(width) x \(height)")
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            logger.log("Error: Failed to create CGContext", level: .error)
            throw NSError(domain: "ImageProcessingError", code: 1003,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create graphics context"])
        }
        
        // Clear the context
        context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        // Draw the image into the context
        context.draw(inputCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Get the standardized image back
        guard let cgImage = context.makeImage() else {
            logger.log("Error: Failed to create image from context", level: .error)
            throw NSError(domain: "ImageProcessingError", code: 1004,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create output image"])
        }
        
        logger.log("Image preprocessing complete")
        return UIImage(cgImage: cgImage)
    }
    
    // Resize image if it's too large
    private func resizeImage(_ image: UIImage, targetSizeMB: Double) -> UIImage? {
        logger.log("Beginning aggressive image resizing to target \(targetSizeMB) MB")
        
        // Start with original dimensions
        var width = image.size.width
        var height = image.size.height
        
        // Iteratively reduce dimensions until we're under target size
        var scaleFactor: CGFloat = 1.0
        var currentImage = image
        
        // Try a few times to get the size right
        for attemptNumber in 1...5 {
            guard let imageData = currentImage.jpegData(compressionQuality: 0.5) else {
                logger.log("Failed to get JPEG data during resize attempt \(attemptNumber)", level: .warning)
                return nil
            }
            
            let fileSizeMB = Double(imageData.count) / 1_000_000.0
            
            if fileSizeMB <= targetSizeMB {
                // We're under the target size
                logger.log("Reached target size on attempt \(attemptNumber): \(String(format: "%.2f", fileSizeMB)) MB")
                return currentImage
            }
            
            logger.log("Resize attempt \(attemptNumber): Image is \(String(format: "%.2f", fileSizeMB)) MB, target is \(targetSizeMB) MB")
            
            // Calculate how much to scale down - more aggressive reduction each time
            let reductionFactor = sqrt(targetSizeMB / fileSizeMB) * 0.8 // Adding extra reduction factor
            scaleFactor *= CGFloat(reductionFactor)
            
            // Calculate new dimensions
            width *= CGFloat(reductionFactor)
            height *= CGFloat(reductionFactor)
            
            logger.log("Reducing dimensions to \(Int(width)) x \(Int(height))")
            
            // Create a new image at the smaller size
            UIGraphicsBeginImageContextWithOptions(CGSize(width: width, height: height), false, 1.0)
            image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
            if let resizedImage = UIGraphicsGetImageFromCurrentImageContext() {
                currentImage = resizedImage
            }
            UIGraphicsEndImageContext()
        }
        
        // If we get here, we've done 5 attempts and still haven't reached target
        logger.log("Failed to reach target size after 5 resize attempts", level: .warning)
        
        // Return the most reduced version anyway
        return currentImage
    }
    
    private func encodeAndSendImageForAnalysis(_ imageData: Data, completion: @escaping (Result<[String], Error>) -> Void) {
        logger.log("Encoding image to base64")
        
        // STEP 1: Encode image
        let base64Image = imageData.base64EncodedString()
        logger.log("Base64 image length: \(base64Image.count) characters")
        
        // STEP 2: Create prompt
        logger.log("Creating prompt for ingredient detection")
        let prompt = """
        This image shows food ingredients. Please identify all food items and ingredients visible in the image.
        Return only a JSON array of strings with the detected ingredients. For example:
        ["Tomato", "Basil", "Garlic", "Olive Oil"]
        """
        
        // STEP 3: Build payload
        logger.log("Building API request payload")
        let payload: [String: Any] = [
            "model": "claude-3-haiku-20240307",
            "max_tokens": 1000,
            "temperature": 0.7,
            "system": "You are an expert ingredient identifier. Only identify food ingredients visible in the image. Return just a JSON array of strings.",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": base64Image]]
                    ]
                ]
            ]
        ]
        
        // STEP 4: Validate JSON
        logger.log("Validating JSON payload")
        do {
            _ = try JSONSerialization.data(withJSONObject: payload, options: [])
            logger.log("Payload JSON is valid, proceeding with request")
            
            // STEP 5: Send the request
            let localSelf = self
            sendRequest(payload: payload) { result in
                localSelf.logger.log("Received API response")
                localSelf.handleApiResponse(result, completion: completion)
            }
            
        } catch {
            logger.log("⚠️ WARNING: Payload JSON is invalid: \(error.localizedDescription)", level: .warning)
            
            // Try to fix the JSON by sanitizing base64
            logger.log("Attempting to sanitize base64 string")
            let sanitizedBase64 = base64Image.replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            
            // Create a new payload with the sanitized base64
            var newPayload = payload
            if var messages = newPayload["messages"] as? [[String: Any]],
               messages.count > 0 {
                
                var userMessage = messages[0]
                if var content = userMessage["content"] as? [[String: Any]],
                   content.count > 1,
                   var imageContent = content[1] as? [String: Any],
                   var source = imageContent["source"] as? [String: Any] {
                
                    logger.log("Rebuilding payload with sanitized base64")
                    source["data"] = sanitizedBase64
                    imageContent["source"] = source
                    content[1] = imageContent
                    userMessage["content"] = content
                    messages[0] = userMessage
                    newPayload["messages"] = messages
                    
                    // Try again
                    do {
                        _ = try JSONSerialization.data(withJSONObject: newPayload, options: [])
                        logger.log("Sanitized payload JSON is valid, proceeding with sanitized base64")
                        
                        // Use the sanitized payload
                        let localSelf = self
                        sendRequest(payload: newPayload) { result in
                            localSelf.logger.log("Received API response (from sanitized payload)")
                            localSelf.handleApiResponse(result, completion: completion)
                        }
                        return
                    } catch {
                        logger.log("⚠️ ERROR: Even sanitized payload is invalid: \(error.localizedDescription)", level: .error)
                        completion(.failure(error))
                    }
                }
            } else {
                logger.log("Failed to access nested payload structure for sanitization", level: .error)
                completion(.failure(error))
            }
        }
    }
    
    // Helper method to handle API response and convert to ingredients format
    private func handleApiResponse(_ result: Result<String, Error>, completion: @escaping (Result<[String], Error>) -> Void) {
        logger.log("Processing API response")
        
        switch result {
        case .success(let responseData):
            logger.log("API request successful, extracting ingredients")
            do {
                // Extract JSON array from response
                if let jsonData = extractJSONArrayFromResponse(responseData) {
                    logger.log("Found JSON array in response")
                    
                    if let ingredients = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String] {
                        logger.log("Successfully parsed \(ingredients.count) ingredients")
                        completion(.success(ingredients))
                    } else {
                        logger.log("JSON parsing failed - not a string array", level: .warning)
                        // Fallback in case JSON parsing fails
                        let ingredients = extractIngredientsFromText(responseData)
                        logger.log("Fallback text extraction found \(ingredients.count) ingredients")
                        completion(.success(ingredients))
                    }
                } else {
                    logger.log("No JSON array found in response, using text extraction", level: .warning)
                    // Fallback in case JSON parsing fails
                    let ingredients = extractIngredientsFromText(responseData)
                    logger.log("Text extraction found \(ingredients.count) ingredients")
                    completion(.success(ingredients))
                }
            } catch {
                logger.log("JSON processing error: \(error.localizedDescription)", level: .error)
                completion(.failure(error))
            }
        case .failure(let error):
            logger.log("API request failed: \(error.localizedDescription)", level: .error)
            completion(.failure(error))
        }
    }
    
    // MARK: - Network Request
    
    private func sendRequest(payload: [String: Any], retryCount: Int = 0, completion: @escaping (Result<String, Error>) -> Void) {
        // Maximum number of retries
        let maxRetries = 3
        let requestID = UUID().uuidString.prefix(8)
        
        logger.log("Preparing request \(requestID) (attempt \(retryCount + 1)/\(maxRetries + 1))")
        
        // STEP 1: Create URL request
        guard let url = URL(string: baseURL) else {
            logger.log("Invalid URL: \(baseURL)", level: .error)
            completion(.failure(NSError(domain: "ClaudeAPIError", code: 1002,
                                        userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 60.0
        
        logger.log("Request \(requestID) headers configured")
        
        // STEP 2: Serialize payload
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
            logger.log("Request \(requestID) body serialized: \(request.httpBody?.count ?? 0) bytes")
        } catch {
            logger.log("Failed to serialize request body: \(error.localizedDescription)", level: .error)
            completion(.failure(error))
            return
        }
        
        // STEP 3: Send the request
        logger.log("Sending request \(requestID) to Claude API")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else {
                self?.logger.log("Self reference lost during network request", level: .error)
                return
            }
            
            // STEP 4: Log request details
            self.logger.log("Request \(requestID) URL: \(url.absoluteString)")
            self.logger.log("Request \(requestID) headers:")
            for (key, value) in request.allHTTPHeaderFields ?? [:] {
                if key.lowercased() == "anthropic-api-key" {
                    self.logger.log("  \(key): [REDACTED]")
                } else {
                    self.logger.log("  \(key): \(value)")
                }
            }
            
            // STEP 5: Handle connection errors
            if let error = error {
                self.logger.log("Request \(requestID) connection error: \(error.localizedDescription)", level: .error)
                
                // Retry logic for network errors
                if retryCount < maxRetries {
                    let delaySeconds = pow(Double(2), Double(retryCount))
                    self.logger.log("Request \(requestID) will retry in \(delaySeconds) seconds", level: .warning)
                    
                    DispatchQueue.global().asyncAfter(deadline: .now() + delaySeconds) {
                        self.sendRequest(payload: payload, retryCount: retryCount + 1, completion: completion)
                    }
                    return
                } else {
                    self.logger.log("Request \(requestID) max retries reached, giving up", level: .error)
                    completion(.failure(error))
                    return
                }
            }
            
            // STEP 6: Check for HTTP errors
            if let httpResponse = response as? HTTPURLResponse {
                self.logger.log("Request \(requestID) received HTTP status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode != 200 {
                    let errorMessage = "HTTP Error: \(httpResponse.statusCode)"
                    let error = NSError(domain: "ClaudeAPIError", code: httpResponse.statusCode,
                                        userInfo: [NSLocalizedDescriptionKey: errorMessage])
                    
                    // Log error details
                    self.logger.log("Request \(requestID) API Error:", level: .error)
                    self.logger.log("  Status Code: \(httpResponse.statusCode)", level: .error)
                    self.logger.log("  Error Domain: \(error.domain)", level: .error)
                    self.logger.log("  Error Code: \(error.code)", level: .error)
                    self.logger.log("  Error Info: \(error.userInfo)", level: .error)
                    
                    // STEP 7: Log response headers
                    self.logger.log("Request \(requestID) response headers:")
                    for (key, value) in httpResponse.allHeaderFields {
                        self.logger.log("  \(key): \(value)")
                    }
                    
                    // STEP 8: Log raw response data
                    if let data = data, let responseString = String(data: data, encoding: .utf8) {
                        self.logger.log("Request \(requestID) raw response data:", level: .debug)
                        self.logger.log(responseString, level: .debug)
                    }
                    
                    // STEP 9: Retry for server errors
                    if (500...599).contains(httpResponse.statusCode) && retryCount < maxRetries {
                        let delaySeconds = pow(Double(2), Double(retryCount)) + Double.random(in: 0.0...1.0)
                        self.logger.log("Request \(requestID) server error (\(httpResponse.statusCode)), retrying in \(delaySeconds) seconds", level: .warning)
                        
                        DispatchQueue.global().asyncAfter(deadline: .now() + delaySeconds) {
                            self.sendRequest(payload: payload, retryCount: retryCount + 1, completion: completion)
                        }
                        return
                    }
                    
                    completion(.failure(error))
                    return
                }
            } else {
                self.logger.log("Request \(requestID) response is not an HTTP response", level: .warning)
            }
            
            // STEP 10: Check for missing data
            guard let data = data else {
                self.logger.log("Request \(requestID) no data received", level: .error)
                completion(.failure(NSError(domain: "ClaudeAPIError", code: 1003,
                                   userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }
            
            // STEP 11: Process response data
            do {
                self.logger.log("Request \(requestID) received \(data.count) bytes of data")
                
                // STEP 12: Parse response into JSON
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    self.logger.log("Request \(requestID) successfully parsed JSON response")
                    
                    // STEP 13: Extract text content
                    // Try current Claude API response format (primary path)
                    if let message = json["message"] as? [String: Any],
                       let content = message["content"] as? [[String: Any]],
                       let firstContent = content.first,
                       let text = firstContent["text"] as? String {
                        self.logger.log("Request \(requestID) found text in primary response format")
                        completion(.success(text))
                    }
                    // Try older Claude API formats (fallback paths)
                    else if let content = json["content"] as? [[String: Any]],
                            let firstContent = content.first,
                            let text = firstContent["text"] as? String {
                        self.logger.log("Request \(requestID) found text in legacy content format")
                        completion(.success(text))
                    }
                    else if let text = json["completion"] as? String {
                        self.logger.log("Request \(requestID) found text in legacy completion format")
                        completion(.success(text))
                    }
                    // Try to extract error message
                    else if let error = json["error"] as? [String: Any],
                            let message = error["message"] as? String {
                        self.logger.log("Request \(requestID) found API error: \(message)", level: .error)
                        completion(.failure(NSError(domain: "ClaudeAPIError", code: 1004,
                                           userInfo: [NSLocalizedDescriptionKey: message])))
                    } else {
                        // We have JSON but couldn't identify the correct structure
                        self.logger.log("Request \(requestID) unknown JSON structure:", level: .error)
                        self.logger.log("\(json)", level: .debug)
                        completion(.failure(NSError(domain: "ClaudeAPIError", code: 1005,
                                           userInfo: [NSLocalizedDescriptionKey: "Failed to parse response structure"])))
                    }
                } else {
                    // STEP 14: Fallback to raw text in case of JSON parsing failure
                    self.logger.log("Request \(requestID) failed to parse as JSON", level: .error)
                    if let responseString = String(data: data, encoding: .utf8) {
                        self.logger.log("Raw response: \(responseString.prefix(100))...", level: .debug)
                    }
                    completion(.failure(NSError(domain: "ClaudeAPIError", code: 1006,
                                       userInfo: [NSLocalizedDescriptionKey: "Failed to parse response as JSON"])))
                }
            } catch {
                self.logger.log("Request \(requestID) error parsing response: \(error.localizedDescription)", level: .error)
                completion(.failure(error))
            }
        }.resume()
        
        logger.log("Request \(requestID) task started")
    }
    
    // Extract JSON array from Claude's text response
    // Add to ClaudeAPIClient if not already there
    private func extractJSONArrayFromResponse(_ response: String) -> Data? {
        logger.log("Extracting JSON array from response")
        
        // Look for JSON array pattern in the response
        let pattern = "\\[\\s*\\{[\\s\\S]*\\}\\s*\\]"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        
        if let match = regex?.firstMatch(in: response, options: [], range: NSRange(response.startIndex..., in: response)),
           let range = Range(match.range, in: response) {
            let jsonString = String(response[range])
            logger.log("Found JSON array: \(jsonString.prefix(50))...")
            return jsonString.data(using: .utf8)
        }
        
        logger.log("No JSON array found in response", level: .warning)
        logger.log("Response: \(response.prefix(100))...", level: .debug)
        return nil
    }
    
    // Extract JSON object from Claude's text response
    private func extractJSONObjectFromResponse(_ response: String) -> Data? {
        logger.log("Extracting JSON object from response")
        
        // Look for JSON object pattern in the response
        let pattern = "\\{[\\s\\S]*\\}"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        
        if let match = regex?.firstMatch(in: response, options: [], range: NSRange(response.startIndex..., in: response)),
           let range = Range(match.range, in: response) {
            let jsonString = String(response[range])
            logger.log("Found JSON object: \(jsonString.prefix(50))...")
            return jsonString.data(using: .utf8)
        }
        
        logger.log("No JSON object found in response", level: .warning)
        return nil
    }
    
    // Fallback method to extract ingredients from text if JSON parsing fails
    private func extractIngredientsFromText(_ text: String) -> [String] {
        logger.log("Attempting to extract ingredients directly from text")
        
        // Split by common separators and clean up
        let possibleIngredients = text.components(separatedBy: CharacterSet(charactersIn: ",.\n[]\""))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 2 } // Basic filtering
        
        logger.log("Raw ingredient candidates: \(possibleIngredients.count) items")
        
        // Remove duplicates
        let uniqueIngredients = Array(Set(possibleIngredients))
        logger.log("Extracted \(uniqueIngredients.count) unique ingredients")
        return uniqueIngredients
    }
    
    // MARK: - Recipe Generation
    
    // Update the generateRecipe function in ClaudeAPIClient
    // Add this to ClaudeAPIClient.swift
    func generateMultipleRecipes(from ingredients: [String], count: Int = 3, dietaryRestrictions: Set<DietaryRestriction> = [], preference: RecipePreference? = nil, completion: @escaping (Result<[Recipe], Error>) -> Void) {
        logger.log("Starting generation of \(count) recipes from \(ingredients.count) ingredients")
        
        // Create a prompt that asks Claude to generate multiple recipes
        let ingredientsText = ingredients.joined(separator: ", ")
        
        // Add dietary restrictions to the prompt if any are selected
        var restrictionsText = ""
        if !dietaryRestrictions.isEmpty {
            let restrictionsList = dietaryRestrictions.map { $0.rawValue }.joined(separator: ", ")
            restrictionsText = """
            
            CRITICAL DIETARY RESTRICTIONS: All recipes MUST comply with these restrictions: \(restrictionsList).
            
            Specific requirements:
            - For vegan restrictions: NO animal products whatsoever (no meat, poultry, fish, dairy, eggs, or honey). Replace these with plant-based alternatives.
            - For vegetarian restrictions: NO meat, poultry, or fish. Dairy and eggs are allowed.
            - For gluten-free restrictions: NO wheat, barley, rye, or regular oats.
            - For dairy-free restrictions: NO milk, cheese, butter, cream, or yogurt.
            - For nut-free restrictions: NO tree nuts or peanuts.
            """
        }
        
        // Add recipe preference to the prompt if selected
        var preferenceText = ""
        if let preference = preference {
            preferenceText = """
            
            RECIPE PREFERENCE: All recipes should be \(preference.rawValue.lowercased()).
            
            Based on this preference:
            """
            
            switch preference {
            case .sweet:
                preferenceText += " Create sweet or dessert recipes (like cakes, cookies, sweet treats, etc)."
            case .savory:
                preferenceText += " Create savory, hearty meals rather than desserts or sweet dishes."
            case .baked:
                preferenceText += " The cooking method should be baking in the oven."
            case .grilled:
                preferenceText += " The cooking method should involve grilling or barbecuing."
            case .fried:
                preferenceText += " The cooking method should involve frying (pan-frying or deep-frying)."
            case .healthy:
                preferenceText += " The recipes should be nutritionally balanced and health-focused."
            case .quick:
                preferenceText += " The recipes should be quick and easy to prepare (under 30 minutes total)."
            case .gourmet:
                preferenceText += " Create fancy, restaurant-quality dishes with sophisticated techniques."
            }
        }
        
        let prompt = """
        Based on these ingredients: \(ingredientsText)
        \(restrictionsText)
        \(preferenceText)
        
        Generate \(count) DIFFERENT creative recipes that use these ingredients. Make each recipe unique in style, cooking method, or cuisine.
        
        Return your response as a JSON array of recipe objects with the following structure:
        
        [
          {
            "title": "Recipe 1 Title",
            "description": "Brief description of dish 1",
            "ingredients": ["Ingredient 1 with quantity", "Ingredient 2 with quantity", "..."],
            "instructions": ["Step 1", "Step 2", "Step 3"],
            "prepTime": "XX mins",
            "cookTime": "XX mins",
            "servings": X,
            "difficulty": "Easy/Medium/Hard",
            "cuisine": "Cuisine Type",
            "nutritionFacts": {
              "calories": XXX,
              "protein": XX,
              "carbs": XX,
              "fat": XX
            }
          },
          {
            "title": "Recipe 2 Title",
            // Same structure as above
          },
          {
            "title": "Recipe 3 Title",
            // Same structure as above
          }
        ]
        
        IMPORTANT: Make ALL \(count) recipes DIFFERENT from each other in cooking style, method, or cuisine.
        Include all ingredients needed for each recipe with measurements.
        Be creative and make diverse, delicious options!
        """
        
        // Build the request payload
        let payload: [String: Any] = [
            "model": "claude-3-haiku-20240307",
            "max_tokens": 4000,  // Increased for multiple recipes
            "temperature": 0.8,  // Slightly higher for more variety
            "system": "You are a creative chef who creates delicious recipes. Always format your response as JSON.",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt]
                    ]
                ]
            ]
        ]
        
        logger.log("Sending multiple recipe generation request")
        
        sendRequest(payload: payload) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let responseData):
                self.logger.log("Multiple recipe generation request successful")
                do {
                    // Extract and parse the JSON recipe array
                    if let jsonData = self.extractJSONArrayFromResponse(responseData),
                       let recipesArray = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String: Any]] {
                        
                        self.logger.log("Successfully extracted JSON recipe array with \(recipesArray.count) recipes")
                        
                        // Parse each recipe
                        var recipes: [Recipe] = []
                        for recipeDict in recipesArray {
                            let recipe = self.parseRecipeFromJSON(
                                recipeDict,
                                ingredients: ingredients,
                                dietaryRestrictions: dietaryRestrictions,
                                preference: preference
                            )
                            recipes.append(recipe)
                        }
                        
                        // If we got fewer recipes than requested, fill with fallback recipes
                        if recipes.count < count {
                            self.logger.log("Only got \(recipes.count) recipes, adding \(count - recipes.count) fallback recipes", level: .warning)
                            for i in recipes.count..<count {
                                // Create slightly varied fallback recipes
                                let fallbackRecipe = self.createFallbackRecipe(
                                    from: ingredients,
                                    responseText: "Fallback Recipe \(i+1)",
                                    dietaryRestrictions: dietaryRestrictions,
                                    preference: preference,
                                    index: i
                                )
                                recipes.append(fallbackRecipe)
                            }
                        }
                        
                        completion(.success(recipes))
                    } else {
                        // Fallback in case JSON parsing fails
                        self.logger.log("Failed to extract JSON recipes array, creating fallback recipes", level: .warning)
                        
                        var fallbackRecipes: [Recipe] = []
                        for i in 0..<count {
                            let fallbackRecipe = self.createFallbackRecipe(
                                from: ingredients,
                                responseText: "Fallback Recipe \(i+1)",
                                dietaryRestrictions: dietaryRestrictions,
                                preference: preference,
                                index: i
                            )
                            fallbackRecipes.append(fallbackRecipe)
                        }
                        
                        completion(.success(fallbackRecipes))
                    }
                } catch {
                    self.logger.log("Error parsing recipes JSON: \(error.localizedDescription)", level: .error)
                    completion(.failure(error))
                }
            case .failure(let error):
                self.logger.log("Multiple recipe generation request failed: \(error.localizedDescription)", level: .error)
                completion(.failure(error))
            }
        }
    }
    
    // Update the parseRecipeFromJSON method to extract the ingredients from Claude's response

    private func parseRecipeFromJSON(_ json: [String: Any], ingredients: [String], dietaryRestrictions: Set<DietaryRestriction>, preference: RecipePreference? = nil) -> Recipe {
        logger.log("Parsing JSON into Recipe object")
        
        // Extract values with fallbacks
        let title = json["title"] as? String ?? "Recipe with \(ingredients.first ?? "Ingredients")"
        let description = json["description"] as? String ?? "A delicious dish made with \(ingredients.joined(separator: ", "))."
        
        // Get instructions
        let instructionsArray = json["instructions"] as? [String] ?? ["Combine all ingredients", "Cook until done", "Serve and enjoy"]
        
        // Get recipe ingredients (with measurements) from JSON if available
        var recipeIngredients: [String] = []
        if let ingredientsArray = json["ingredients"] as? [String] {
            recipeIngredients = ingredientsArray
            logger.log("Found \(recipeIngredients.count) ingredients in JSON response")
        } else {
            logger.log("No ingredients array in JSON, using detected ingredients", level: .warning)
        }
        
        let prepTime = json["prepTime"] as? String ?? "\(5 + ingredients.count * 2) mins"
        let cookTime = json["cookTime"] as? String ?? "20 mins"
        let servings = json["servings"] as? Int ?? 2 + Int.random(in: 0...2)
        let difficulty = json["difficulty"] as? String ?? (ingredients.count <= 4 ? "Easy" : "Medium")
        let cuisine = json["cuisine"] as? String ?? "Fusion"
        
        logger.log("Recipe basics - Title: \(title), Prep: \(prepTime), Cook: \(cookTime)")
        
        // Extract nutrition facts
        var nutritionFacts: NutritionFacts? = nil
        if let nutritionDict = json["nutritionFacts"] as? [String: Any] {
            logger.log("Found nutrition facts in JSON")
            let calories = nutritionDict["calories"] as? Int ?? 300
            let protein = nutritionDict["protein"] as? Int ?? 10
            let carbs = nutritionDict["carbs"] as? Int ?? 30
            let fat = nutritionDict["fat"] as? Int ?? 15
            
            nutritionFacts = NutritionFacts(calories: calories, protein: protein, carbs: carbs, fat: fat)
            logger.log("Nutrition facts - Calories: \(calories), Protein: \(protein)g, Carbs: \(carbs)g, Fat: \(fat)g")
        } else {
            logger.log("No nutrition facts found in JSON", level: .debug)
        }
        
        logger.log("Successfully created Recipe object")
        return Recipe(
                title: title,
                detectedIngredients: ingredients,
                recipeIngredients: recipeIngredients,
                instructions: instructionsArray,
                prepTime: prepTime,
                cookTime: cookTime,
                servings: servings,
                difficulty: difficulty,
                cuisine: cuisine,
                imageURL: nil,
                description: description,
                nutritionFacts: nutritionFacts,
                dietaryRestrictions: dietaryRestrictions,
                preference: preference
            )
    }

    // Also update the createFallbackRecipe method
    private func createFallbackRecipe(from ingredients: [String], responseText: String, dietaryRestrictions: Set<DietaryRestriction>, preference: RecipePreference? = nil, index: Int = 0) -> Recipe {
        logger.log("Creating fallback recipe #\(index+1)")
        
        // Add variety to fallback recipes based on index
        let cuisines = ["Italian", "Mexican", "Asian", "Mediterranean", "American", "Indian", "French"]
        let cookingMethods = ["baked", "grilled", "stir-fried", "sautéed", "steamed", "roasted"]
        
        // Vary the title based on index
        var title: String
        if let preference = preference {
            title = "\(preference.rawValue) \(cookingMethods[index % cookingMethods.count].capitalized) \(ingredients.first ?? "Ingredients")"
        } else {
            title = "\(cookingMethods[index % cookingMethods.count].capitalized) \(ingredients.first ?? "Ingredients")"
        }
        
        // Vary the cuisine
        let cuisine = cuisines[index % cuisines.count]
        
        // Create varied instructions
        var instructions: [String] = [
            "Prepare all ingredients by washing and chopping as needed.",
            "Heat a pan over medium heat with a little oil or butter."
        ]
        
        // Add cooking method specific instruction
        switch index % cookingMethods.count {
        case 0: // baked
            instructions.append("Preheat oven to 375°F (190°C).")
            instructions.append("Place ingredients in a baking dish and season with salt and pepper.")
            instructions.append("Bake for 25-30 minutes until golden brown.")
        case 1: // grilled
            instructions.append("Preheat grill to medium-high heat.")
            instructions.append("Season ingredients with salt, pepper, and your favorite spices.")
            instructions.append("Grill for 5-7 minutes per side until properly cooked.")
        case 2: // stir-fried
            instructions.append("Heat wok or large pan over high heat until very hot.")
            instructions.append("Add ingredients in order of cooking time, stir-frying quickly.")
            instructions.append("Add sauce at the end and toss until everything is coated.")
        case 3: // sautéed
            instructions.append("Heat oil in a large skillet over medium-high heat.")
            instructions.append("Add ingredients one by one, starting with aromatics.")
            instructions.append("Cook while stirring frequently until ingredients are tender.")
        case 4: // steamed
            instructions.append("Set up a steamer basket over simmering water.")
            instructions.append("Arrange ingredients in the steamer, being careful not to overcrowd.")
            instructions.append("Steam until ingredients are tender but still vibrant.")
        case 5: // roasted
            instructions.append("Preheat oven to 425°F (220°C).")
            instructions.append("Toss ingredients with oil and seasoning on a baking sheet.")
            instructions.append("Roast for 20-25 minutes, turning halfway through cooking.")
        default:
            instructions.append("Cook ingredients using your preferred method.")
        }
        
        instructions.append("Serve hot and enjoy your creation.")
        
        // Create description with variety
        let descriptions = [
            "A delicious \(cuisine.lowercased()) inspired dish featuring fresh ingredients.",
            "This \(cookingMethods[index % cookingMethods.count]) specialty brings out the natural flavors of your ingredients.",
            "A quick and easy \(cuisine) recipe perfect for any occasion.",
            "Enjoy this flavorful dish that highlights the best of \(cuisine) cuisine.",
            "A simple yet delicious way to use your available ingredients."
        ]
        
        var description = descriptions[index % descriptions.count]
        
        // Add preference to description if provided
        if let preference = preference {
            description += " This \(preference.rawValue.lowercased()) recipe will satisfy your cravings."
        }
        
        // Add dietary restrictions to description if any
        if !dietaryRestrictions.isEmpty {
            let restrictionsList = dietaryRestrictions.map { $0.rawValue }.joined(separator: ", ")
            description += " Suitable for \(restrictionsList) diets."
        }
        
        // Create varied nutrition facts
        let baseCalories = 250 + ingredients.count * 25
        let baseProtein = 5 + ingredients.count * 2
        let baseCarbs = 15 + ingredients.count * 3
        let baseFat = 8 + ingredients.count
        
        let nutritionFacts = NutritionFacts(
            calories: baseCalories + (index * 25),
            protein: baseProtein + (index * 1),
            carbs: baseCarbs + (index * 2),
            fat: baseFat + (index * 1)
        )
        
        // Create varied prep and cook times
        let prepTime = "\((5 + ingredients.count) + (index * 2)) mins"
        let cookTime = "\((10 + ingredients.count * 2) + (index * 5)) mins"
        
        // Return the fallback recipe
        return Recipe(
            title: title,
            detectedIngredients: ingredients,
            recipeIngredients: ingredients.map { "\(["1 cup", "2 tablespoons", "1/2 teaspoon", "3", "a handful of"].randomElement() ?? "") \($0)" },
            instructions: instructions,
            prepTime: prepTime,
            cookTime: cookTime,
            servings: 2 + (index % 3),
            difficulty: ingredients.count <= 3 ? "Easy" : (index % 3 == 0 ? "Medium" : "Hard"),
            cuisine: cuisine,
            imageURL: nil,
            description: description,
            nutritionFacts: nutritionFacts,
            dietaryRestrictions: dietaryRestrictions,
            preference: preference
        )
    }
    // MARK: - Debugging Helpers
    
    // Function to dump full logs - useful for debugging
    func getFullLogs() -> String {
        return logger.getFullLog()
    }
}
