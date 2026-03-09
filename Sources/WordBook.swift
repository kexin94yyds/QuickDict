import Foundation

struct WordEntry: Codable {
    let id: UUID
    let word: String
    let sentence: String
    let date: Date
    var reviewCount: Int
    var lastReview: Date?
    
    init(word: String, sentence: String) {
        self.id = UUID()
        self.word = word
        self.sentence = sentence
        self.date = Date()
        self.reviewCount = 0
        self.lastReview = nil
    }
}

class WordBook {
    static let shared = WordBook()
    
    private var entries: [WordEntry] = []
    private let fileURL: URL
    
    private init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documentsPath.appendingPathComponent("QuickDict_WordBook.json")
        load()
    }
    
    func add(word: String, sentence: String) {
        let entry = WordEntry(word: word, sentence: sentence)
        entries.insert(entry, at: 0)
        save()
    }
    
    func getAll() -> [WordEntry] {
        return entries
    }
    
    func getCount() -> Int {
        return entries.count
    }
    
    func markReviewed(id: UUID) {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].reviewCount += 1
            entries[index].lastReview = Date()
            save()
        }
    }
    
    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }
    
    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) {
            try? data.write(to: fileURL)
        }
    }
    
    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([WordEntry].self, from: data) {
            entries = loaded
        }
    }
}
