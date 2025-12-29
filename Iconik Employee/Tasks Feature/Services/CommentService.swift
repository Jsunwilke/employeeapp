//
//  CommentService.swift
//  Iconik Employee
//
//  Service layer for task comments
//  Handles subcollection: /tasks/{taskId}/comments/{commentId}
//

import Foundation
import Supabase
import Combine

@MainActor
class CommentService: ObservableObject {
    static let shared = CommentService()

    private let supabase = SupabaseManager.shared.client
    private let commentsTable = "task_comments"

    @Published var comments: [TaskComment] = []
    @Published var isLoading = false
    @Published var error: Error?

    private var channels: [String: RealtimeChannelV2] = [:]

    private init() {}

    // MARK: - Create Comment

    /// Add a new comment to a task
    func addComment(
        to taskId: String,
        text: String,
        userId: String,
        userName: String,
        mentions: [CommentMention] = [],
        attachments: [CommentAttachment] = []
    ) async throws -> TaskComment {
        var comment = TaskComment(
            id: UUID().uuidString,
            taskId: taskId,
            userId: userId,
            userName: userName,
            text: text,
            mentions: mentions,
            attachments: attachments,
            createdAt: Date(),
            updatedAt: Date()
        )

        // Insert into Supabase
        try await supabase
            .from(commentsTable)
            .insert(comment)
            .execute()

        // Increment task's commentCount
        do {
            try await incrementCommentCount(taskId: taskId)
        } catch {
            // Comment was created but count increment failed
            print("⚠️ Comment created but count increment failed: \(error.localizedDescription)")
        }

        // Add to local state
        comments.append(comment)

        // TODO: Create notifications for mentions
        // TODO: Auto-watch task for mentioned users
        // TODO: Notify watchers about new comment
        // TODO: Log activity (COMMENT_ADDED)

        return comment
    }

    // MARK: - Read Comments

    /// Fetch all comments for a task
    func fetchComments(for taskId: String) async throws -> [TaskComment] {
        isLoading = true
        defer { isLoading = false }

        let fetchedComments: [TaskComment] = try await supabase
            .from(commentsTable)
            .select()
            .eq("task_id", value: taskId)
            .order("created_at", ascending: true)
            .execute()
            .value

        comments = fetchedComments
        return fetchedComments
    }

    /// Get a single comment by ID
    func getComment(taskId: String, commentId: String) async throws -> TaskComment {
        let comments: [TaskComment] = try await supabase
            .from(commentsTable)
            .select()
            .eq("id", value: commentId)
            .eq("task_id", value: taskId)
            .limit(1)
            .execute()
            .value

        guard let comment = comments.first else {
            throw NSError(domain: "CommentService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Comment not found"])
        }

        return comment
    }

    // MARK: - Real-time Listener

    /// Start listening to comments for a task
    func startListening(to taskId: String) {
        // Remove existing listener if any
        stopListening(taskId: taskId)

        let channelKey = "comments-\(taskId)"
        let channel = supabase.channel(channelKey)

        _ = channel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: commentsTable,
            filter: "task_id=eq.\(taskId)"
        ) { [weak self] _ in
            Task { @MainActor in
                do {
                    let fetchedComments = try await self?.fetchComments(for: taskId) ?? []
                    self?.comments = fetchedComments
                } catch {
                    print("❌ Comment listener error: \(error.localizedDescription)")
                    self?.error = error
                }
            }
        }

        Task {
            await channel.subscribe()

            // Initial fetch
            do {
                let fetchedComments = try await fetchComments(for: taskId)
                comments = fetchedComments
            } catch {
                print("❌ Error on initial comments fetch: \(error)")
            }
        }

        channels[taskId] = channel
    }

    /// Stop listening to comments for a specific task
    func stopListening(taskId: String) {
        if let channel = channels[taskId] {
            Task {
                await channel.unsubscribe()
            }
            channels.removeValue(forKey: taskId)
        }
    }

    /// Stop all comment listeners
    func stopAllListeners() {
        for (_, channel) in channels {
            Task {
                await channel.unsubscribe()
            }
        }
        channels.removeAll()
    }

    // MARK: - Update Comment

    /// Update an existing comment
    func updateComment(
        taskId: String,
        commentId: String,
        text: String,
        mentions: [CommentMention] = []
    ) async throws {
        var comment = try await getComment(taskId: taskId, commentId: commentId)
        comment.text = text
        comment.mentions = mentions
        comment.updatedAt = Date()

        try await supabase
            .from(commentsTable)
            .update(comment)
            .eq("id", value: commentId)
            .execute()

        // Update local state
        if let index = comments.firstIndex(where: { $0.id == commentId }) {
            comments[index].text = text
            comments[index].mentions = mentions
            comments[index].updatedAt = Date()
        }

        // TODO: Log activity (COMMENT_UPDATED)
    }

    // MARK: - Delete Comment

    /// Delete a comment
    func deleteComment(taskId: String, commentId: String) async throws {
        try await supabase
            .from(commentsTable)
            .delete()
            .eq("id", value: commentId)
            .execute()

        // Decrement task's commentCount
        do {
            try await decrementCommentCount(taskId: taskId)
        } catch {
            // Comment was deleted but count decrement failed
            print("⚠️ Comment deleted but count decrement failed: \(error.localizedDescription)")
        }

        // Remove from local state
        comments.removeAll { $0.id == commentId }

        // TODO: Log activity (COMMENT_DELETED)
    }

    // MARK: - Comment Count Management

    /// Increment the commentCount field on the task
    private func incrementCommentCount(taskId: String) async throws {
        // Get current task
        var task = try await TaskService.shared.getTask(id: taskId)
        task.commentCount += 1
        task.updatedAt = Date()

        // Update task
        try await TaskService.shared.updateTask(task)
    }

    /// Decrement the commentCount field on the task
    private func decrementCommentCount(taskId: String) async throws {
        // Get current task
        var task = try await TaskService.shared.getTask(id: taskId)
        task.commentCount = max(0, task.commentCount - 1)
        task.updatedAt = Date()

        // Update task
        try await TaskService.shared.updateTask(task)
    }

    // MARK: - Attachment Operations

    /// Add attachment to existing comment
    func addAttachment(
        to commentId: String,
        in taskId: String,
        attachment: CommentAttachment
    ) async throws {
        var comment = try await getComment(taskId: taskId, commentId: commentId)
        comment.attachments.append(attachment)
        comment.updatedAt = Date()

        try await supabase
            .from(commentsTable)
            .update(comment)
            .eq("id", value: commentId)
            .execute()

        // TODO: Log activity (ATTACHMENT_UPLOADED)
    }

    /// Remove attachment from comment
    func removeAttachment(
        from commentId: String,
        in taskId: String,
        attachment: CommentAttachment
    ) async throws {
        var comment = try await getComment(taskId: taskId, commentId: commentId)
        comment.attachments.removeAll { $0.fileUrl == attachment.fileUrl }
        comment.updatedAt = Date()

        try await supabase
            .from(commentsTable)
            .update(comment)
            .eq("id", value: commentId)
            .execute()

        // TODO: Delete file from Supabase Storage
        // TODO: Log activity (ATTACHMENT_DELETED)
    }

    // MARK: - Utility Methods

    /// Get comment count for a task without fetching all comments
    func getCommentCount(for taskId: String) async throws -> Int {
        let task = try await TaskService.shared.getTask(id: taskId)
        return task.commentCount
    }

    /// Clear local comment state
    func clearComments() {
        comments.removeAll()
    }
}
