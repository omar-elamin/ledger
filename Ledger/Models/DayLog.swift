import Foundation

struct DayLog: Identifiable {
    let id = UUID()
    let date: Date
    let calories: Int
    let protein: Int
    let eaten: [String]
    let trained: [String]
    let body: [String]
    let summary: String
}
