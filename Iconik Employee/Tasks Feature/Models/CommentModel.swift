//
//  CommentModel.swift
//  Iconik Employee
//
//  Model for task comments with mentions and attachments
//  Migrated to Supabase
//

import Foundation
import Supabase

// MARK: - Mention Model

struct CommentMention: Codable, Equatable {
    var userId: String
    var userName: String

    init(userId: String, userName: String) {
        self.userId = userId
        self.userName = userName
    }
}

// MARK: - Attachment Model

struct CommentAttachment: Codable, Equatable {
    var fileName: String
    var fileUrl: String
    var fileType: String
    var fileSize: Int

    init(fileName: String, fileUrl: String, fileType: String, fileSize: Int) {
        self.fileName = fileName
        self.fileUrl = fileUrl
        self.fileType = fileType
        self.fileSize = fileSize
    }

    /// Human-readable file size (e.g., "2.5 MB")
    var fileSizeFormatted: String {
        let bytes = Double(fileSize)
        if bytes < 1024 {
            return "\(fileSize) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", bytes / 1024)
        } else if bytes < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", bytes / (1024 * 1024))
        } else {
            return String(format: "%.1f GB", bytes / (1024 * 1024 * 1024))
        }
    }

    /// Check if file is an image
    var isImage: Bool {
        let imageTypes = ["image/jpeg", "image/jpg", "image/png", "image/gif", "image/webp"]
        return imageTypes.contains(fileType.lowercased())
    }

    /// Check if file is a document
    var isDocument: Bool {
        let docTypes = ["application/pdf", "application/msword", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"]
        return docTypes.contains(fileType.lowercased())
    }
}

// MARK: - Comment Model

struct TaskComment: Identifiable, Codable {
    var id: String
    var taskId: String
    var userId: String
    var text: String
    var mentions: [CommentMention]
    var attachments: [CommentAttachment]
    var createdAt: Date
    var updatedAt: Date

    // Not stored in database - populated from user lookup
    var userName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case userId = "user_id"
        case text
        case mentions
        case attachments
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // MARK: - Custom Decoder (userName not in database)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        taskId = try container.decode(String.self, forKey: .taskId)
        userId = try container.decode(String.self, forKey: .userId)
        text = try container.decode(String.self, forKey: .text)
        mentions = try container.decodeIfPresent([CommentMention].self, forKey: .mentions) ?? []
        attachments = try container.decodeIfPresent([CommentAttachment].self, forKey: .attachments) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        userName = nil // Must be populated separately via user lookup
    }

    // MARK: - Initializer

    init(
        id: String = UUID().uuidString,
        taskId: String,
        userId: String,
        userName: String? = nil,
        text: String,
        mentions: [CommentMention] = [],
        attachments: [CommentAttachment] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.taskId = taskId
        self.userId = userId
        self.userName = userName
        self.text = text
        self.mentions = mentions
        self.attachments = attachments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Display name - returns userName if available, otherwise a fallback
    var displayName: String {
        return userName ?? "Unknown User"
    }

    // MARK: - Note
    // TaskComment uses Codable for automatic Supabase JSON encoding/decoding
    // CodingKeys map Swift camelCase properties to Supabase snake_case fields

    // MARK: - Computed Properties

    /// Check if comment was edited
    var isEdited: Bool {
        return updatedAt.timeIntervalSince(createdAt) > 1 // More than 1 second difference
    }

    /// Get list of mentioned user IDs
    var mentionedUserIds: [String] {
        return mentions.map { $0.userId }
    }

    /// Check if a specific user is mentioned
    func mentions(userId: String) -> Bool {
        return mentionedUserIds.contains(userId)
    }

    /// Get display text for time ago (e.g., "2 hours ago")
    var timeAgoText: String {
        let now = Date()
        let interval = now.timeIntervalSince(createdAt)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: createdAt)
        }
    }
}

// MARK: - Comment Extensions

extension TaskComment {
    /// Parse @mentions from text and extract user IDs
    /// Format: @[userName](userId)
    static func parseMentions(from text: String, allUsers: [(id: String, name: String)]) -> [CommentMention] {
        var mentions: [CommentMention] = []

        // Simple regex pattern to find @mentions
        // This is a basic implementation - enhance as needed
        let pattern = "@\\[(.*?)\\]\\((.*?)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return mentions
        }

        let nsString = text as NSString
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

        for match in results {
            if match.numberOfRanges == 3 {
                let userNameRange = match.range(at: 1)
                let userIdRange = match.range(at: 2)

                let userName = nsString.substring(with: userNameRange)
                let userId = nsString.substring(with: userIdRange)

                mentions.append(CommentMention(userId: userId, userName: userName))
            }
        }

        return mentions
    }

    /// Convert mentions in text to plain text (remove markdown formatting)
    var plainText: String {
        var result = text

        // Replace @[userName](userId) with @userName
        let pattern = "@\\[(.*?)\\]\\(.*?\\)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))

            // Process matches in reverse to maintain indices
            for match in matches.reversed() {
                if match.numberOfRanges >= 2 {
                    let fullRange = match.range
                    let userNameRange = match.range(at: 1)
                    let userName = nsString.substring(with: userNameRange)

                    result = (result as NSString).replacingCharacters(in: fullRange, with: "@\(userName)")
                }
            }
        }

        return result
    }
}
