//
//  CommentService.swift
//  Iconik Employee
//
//  Service layer for task comments
//  Handles subcollection: /tasks/{taskId}/comments/{commentId}
//

import Foundation
import FirebaseFirestore
import Combine

class CommentService: ObservableObject {
    static let shared = CommentService()

    private let db = Firestore.firestore()
    private let tasksCollection = "tasks"
    private let commentsSubcollection = "comments"

    @Published var comments: [TaskComment] = []
    @Published var isLoading = false
    @Published var error: Error?

    private var listeners: [String: ListenerRegistration] = [:]

    private init() {}

    // MARK: - Create Comment

    /// Add a new comment to a task
    func addComment(
        to taskId: String,
        text: String,
        userId: String,
        userName: String,
        mentions: [CommentMention] = [],
        attachments: [CommentAttachment] = [],
        completion: @escaping (Result<TaskComment, Error>) -> Void
    ) {
        let comment = TaskComment(
            id: UUID().uuidString,
            userId: userId,
            userName: userName,
            text: text,
            mentions: mentions,
            attachments: attachments,
            createdAt: Date(),
            updatedAt: Date()
        )

        let commentRef = db.collection(tasksCollection)
            .document(taskId)
            .collection(commentsSubcollection)
            .document(comment.id)

        commentRef.setData(comment.toFirestoreData()) { [weak self] error in
            if let error = error {
                completion(.failure(error))
                return
            }

            // Increment task's commentCount
            self?.incrementCommentCount(taskId: taskId) { result in
                switch result {
                case .success:
                    // Add to local state
                    self?.comments.append(comment)
                    completion(.success(comment))

                    // TODO: Create notifications for mentions
                    // TODO: Auto-watch task for mentioned users
                    // TODO: Notify watchers about new comment
                    // TODO: Log activity (COMMENT_ADDED)

                case .failure(let error):
                    // Comment was created but count increment failed
                    print("⚠️ Comment created but count increment failed: \(error.localizedDescription)")
                    completion(.success(comment))
                }
            }
        }
    }

    // MARK: - Read Comments

    /// Fetch all comments for a task
    func fetchComments(for taskId: String, completion: @escaping (Result<[TaskComment], Error>) -> Void) {
        isLoading = true

        db.collection(tasksCollection)
            .document(taskId)
            .collection(commentsSubcollection)
            .order(by: "createdAt", descending: false)
            .getDocuments { [weak self] snapshot, error in
                self?.isLoading = false

                if let error = error {
                    self?.error = error
                    completion(.failure(error))
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }

                let comments = documents.compactMap { TaskComment(from: $0) }
                self?.comments = comments
                completion(.success(comments))
            }
    }

    /// Get a single comment by ID
    func getComment(taskId: String, commentId: String, completion: @escaping (Result<TaskComment, Error>) -> Void) {
        db.collection(tasksCollection)
            .document(taskId)
            .collection(commentsSubcollection)
            .document(commentId)
            .getDocument { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let snapshot = snapshot, snapshot.exists else {
                    completion(.failure(NSError(domain: "CommentService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Comment not found"])))
                    return
                }

                if let comment = TaskComment(from: snapshot) {
                    completion(.success(comment))
                } else {
                    completion(.failure(NSError(domain: "CommentService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to parse comment"])))
                }
            }
    }

    // MARK: - Real-time Listener

    /// Start listening to comments for a task
    func startListening(to taskId: String) {
        // Remove existing listener if any
        stopListening(taskId: taskId)

        let listener = db.collection(tasksCollection)
            .document(taskId)
            .collection(commentsSubcollection)
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("❌ Comment listener error: \(error.localizedDescription)")
                    self?.error = error
                    return
                }

                guard let documents = snapshot?.documents else { return }

                let comments = documents.compactMap { TaskComment(from: $0) }
                self?.comments = comments
            }

        listeners[taskId] = listener
    }

    /// Stop listening to comments for a specific task
    func stopListening(taskId: String) {
        if let listener = listeners[taskId] {
            listener.remove()
            listeners.removeValue(forKey: taskId)
        }
    }

    /// Stop all comment listeners
    func stopAllListeners() {
        for (_, listener) in listeners {
            listener.remove()
        }
        listeners.removeAll()
    }

    // MARK: - Update Comment

    /// Update an existing comment
    func updateComment(
        taskId: String,
        commentId: String,
        text: String,
        mentions: [CommentMention] = [],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let updates: [String: Any] = [
            "text": text,
            "mentions": mentions.map { ["userId": $0.userId, "userName": $0.userName] },
            "updatedAt": Timestamp(date: Date())
        ]

        db.collection(tasksCollection)
            .document(taskId)
            .collection(commentsSubcollection)
            .document(commentId)
            .updateData(updates) { [weak self] error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                // Update local state
                if let index = self?.comments.firstIndex(where: { $0.id == commentId }) {
                    self?.comments[index].text = text
                    self?.comments[index].mentions = mentions
                    self?.comments[index].updatedAt = Date()
                }

                completion(.success(()))

                // TODO: Log activity (COMMENT_UPDATED)
            }
    }

    // MARK: - Delete Comment

    /// Delete a comment
    func deleteComment(taskId: String, commentId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        db.collection(tasksCollection)
            .document(taskId)
            .collection(commentsSubcollection)
            .document(commentId)
            .delete { [weak self] error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                // Decrement task's commentCount
                self?.decrementCommentCount(taskId: taskId) { result in
                    switch result {
                    case .success:
                        // Remove from local state
                        self?.comments.removeAll { $0.id == commentId }
                        completion(.success(()))

                        // TODO: Log activity (COMMENT_DELETED)

                    case .failure(let error):
                        // Comment was deleted but count decrement failed
                        print("⚠️ Comment deleted but count decrement failed: \(error.localizedDescription)")
                        self?.comments.removeAll { $0.id == commentId }
                        completion(.success(()))
                    }
                }
            }
    }

    // MARK: - Comment Count Management

    /// Increment the commentCount field on the task
    private func incrementCommentCount(taskId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        db.collection(tasksCollection)
            .document(taskId)
            .updateData([
                "commentCount": FieldValue.increment(Int64(1)),
                "updatedAt": Timestamp(date: Date())
            ]) { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
    }

    /// Decrement the commentCount field on the task
    private func decrementCommentCount(taskId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        db.collection(tasksCollection)
            .document(taskId)
            .updateData([
                "commentCount": FieldValue.increment(Int64(-1)),
                "updatedAt": Timestamp(date: Date())
            ]) { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
    }

    // MARK: - Attachment Operations

    /// Add attachment to existing comment
    func addAttachment(
        to commentId: String,
        in taskId: String,
        attachment: CommentAttachment,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        db.collection(tasksCollection)
            .document(taskId)
            .collection(commentsSubcollection)
            .document(commentId)
            .updateData([
                "attachments": FieldValue.arrayUnion([[
                    "fileName": attachment.fileName,
                    "fileUrl": attachment.fileUrl,
                    "fileType": attachment.fileType,
                    "fileSize": attachment.fileSize
                ]]),
                "updatedAt": Timestamp(date: Date())
            ]) { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                    // TODO: Log activity (ATTACHMENT_UPLOADED)
                }
            }
    }

    /// Remove attachment from comment
    func removeAttachment(
        from commentId: String,
        in taskId: String,
        attachment: CommentAttachment,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        db.collection(tasksCollection)
            .document(taskId)
            .collection(commentsSubcollection)
            .document(commentId)
            .updateData([
                "attachments": FieldValue.arrayRemove([[
                    "fileName": attachment.fileName,
                    "fileUrl": attachment.fileUrl,
                    "fileType": attachment.fileType,
                    "fileSize": attachment.fileSize
                ]]),
                "updatedAt": Timestamp(date: Date())
            ]) { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                    // TODO: Delete file from Firebase Storage
                    // TODO: Log activity (ATTACHMENT_DELETED)
                }
            }
    }

    // MARK: - Utility Methods

    /// Get comment count for a task without fetching all comments
    func getCommentCount(for taskId: String, completion: @escaping (Result<Int, Error>) -> Void) {
        db.collection(tasksCollection)
            .document(taskId)
            .collection(commentsSubcollection)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                let count = snapshot?.documents.count ?? 0
                completion(.success(count))
            }
    }

    /// Clear local comment state
    func clearComments() {
        comments.removeAll()
    }
}
