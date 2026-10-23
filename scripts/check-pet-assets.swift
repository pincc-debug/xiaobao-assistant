import Foundation
import ImageIO
let ids = ["creator_engineer", "creator_plush", "female", "male", "scholar", "professor", "astronaut", "doctor", "finance", "engineer", "retail", "chef", "lawyer", "agriculture", "polyv_female", "polyv_male", "property", "tourism", "logistics", "developer", "beauty", "corporate"]
for id in ids {
    let path = "Sources/Assistant/Resources/\(id).png"
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Missing or invalid: \(id)") }
    precondition(abs(image.height - image.width * 2) <= 2, "Unexpected atlas grid: \(id)")
    precondition(image.alphaInfo != .none && image.alphaInfo != .noneSkipFirst && image.alphaInfo != .noneSkipLast, "Missing alpha: \(id)")
    for row in 0..<8 {
        for column in 0..<4 {
            let rect = CGRect(x: column * image.width / 4, y: row * image.height / 8, width: image.width / 4, height: image.height / 8)
            precondition(image.cropping(to: rect) != nil, "Invalid frame: \(id) \(row) \(column)")
        }
    }
    print("OK \(id): \(image.width)x\(image.height), 32 frames, alpha")
}
