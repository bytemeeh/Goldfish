import Foundation

let u1 = UUID()
let u2 = UUID()

let str1 = u1.uuidString
let str2 = u2.uuidString

let key = [str1, str2].sorted().joined(separator: "-")

let split = key.split(separator: "-")

print(UUID(uuidString: String(split[0])) == nil ? "FAILED" : "SUCCESS")

