//
//  CommentModel.swift
//  Iconik Employee
//
//  Model for task comments with mentions and attachments
//  Stored in subcollection: /tasks/{taskId}/comments/{commentId}
//

import Foundation
import FirebaseFirestore

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
    var userId: String
    var userName: String
    var text: String
    var mentions: [CommentMention]
    var attachments: [CommentAttachment]
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case userName
        case text
        case mentions
        case attachments
        case createdAt
        case updatedAt
    }

    // MARK: - Initializer

    init(
        id: String = UUID().uuidString,
        userId: String,
        userName: String,
        text: String,
        mentions: [CommentMention] = [],
        attachments: [CommentAttachment] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.userName = userName
        self.text = text
        self.mentions = mentions
        self.attachments = attachments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Firestore Conversion

    init?(from document: DocumentSnapshot) {
        guard let data = document.data(),
              let userId = data["userId"] as? String,
              let userName = data["userName"] as? String,
              let text = data["text"] as? String,
              let createdAtTimestamp = data["createdAt"] as? Timestamp,
              let updatedAtTimestamp = data["updatedAt"] as? Timestamp else {
            return nil
        }

        self.id = document.documentID
        self.userId = userId
        self.userName = userName
        self.text = text
        self.createdAt = createdAtTimestamp.dateValue()
        self.updatedAt = updatedAtTimestamp.dateValue()

        // Parse mentions
        if let mentionsData = data["mentions"] as? [[String: Any]] {
            self.mentions = mentionsData.compactMap { mentionDict in
                guard let userId = mentionDict["userId"] as? String,
                      let userName = mentionDict["userName"] as? String else {
                    return nil
                }
                return CommentMention(userId: userId, userName: userName)
            }
        } else {
            self.mentions = []
        }

        // Parse attachments
        if let attachmentsData = data["attachments"] as? [[String: Any]] {
            self.attachments = attachmentsData.compactMap { attachmentDict in
                guard let fileName = attachmentDict["fileName"] as? String,
                      let fileUrl = attachmentDict["fileUrl"] as? String,
                      let fileType = attachmentDict["fileType"] as? String,
                      let fileSize = attachmentDict["fileSize"] as? Int else {
                    return nil
                }
                return CommentAttachment(
                    fileName: fileName,
                    fileUrl: fileUrl,
                    fileType: fileType,
                    fileSize: fileSize
                )
            }
        } else {
            self.attachments = []
        }
    }

    func toFirestoreData() -> [String: Any] {
        return [
            "userId": userId,
            "userName": userName,
            "text": text,
            "mentions": mentions.map { ["userId": $0.userId, "userName": $0.userName] },
            "attachments": attachments.map {
                [
                    "fileName": $0.fileName,
                    "fileUrl": $0.fileUrl,
                    "fileType": $0.fileType,
                    "fileSize": $0.fileSize
                ]
            },
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt)
        ]
    }

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
