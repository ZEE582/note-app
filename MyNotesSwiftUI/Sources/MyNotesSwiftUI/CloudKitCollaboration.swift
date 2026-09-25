import Foundation
#if canImport(Combine)
import Combine
#endif
#if canImport(UIKit)
import UIKit
#endif

#if canImport(CloudKit)
import CloudKit

/// CloudKit boundary for local-first notes with real-time collaboration.
/// The shared root is a CloudKit snapshot, deliberately separate from SwiftData.
/// This avoids mutating or replacing the user's local source of truth.
actor CloudKitCollaboration {
    static let shared = CloudKitCollaboration()
    /// `CKContainer(identifier:)` raises an Objective-C exception rather than
    /// throwing when the identifier is not in the signed entitlements, so it
    /// cannot be built in a stored property: a build without the iCloud
    /// capability would raise inside `shared` during `init()` and take the app
    /// down at launch. Resolving it on first use keeps launch safe and defers
    /// the failure to the point where sharing is actually attempted.
    private lazy var database = CKContainer(identifier: "iCloud.com.mynotes.app").privateCloudDatabase
    private var subscription: CKDatabaseSubscription?
    private var activeCollaborators: [String: CollaboratorInfo] = [:]
    
    struct ShareResult {
        let recordName: String
        let url: URL?
    }
    
    struct CollaboratorInfo {
        let userID: String
        let name: String
        let lastSeen: Date
        let isEditing: Bool
    }
    
    struct SyncUpdate {
        let noteID: UUID
        let title: String
        let content: String
        let folder: String
        let tags: [String]
        let updatedAt: Date
        let collaboratorID: String?
    }
    
    #if canImport(Combine)
    private let syncUpdateSubject = PassthroughSubject<SyncUpdate, Never>()
    var syncUpdatePublisher: AnyPublisher<SyncUpdate, Never> {
        syncUpdateSubject.eraseToAnyPublisher()
    }
    
    private let collaboratorSubject = PassthroughSubject<[CollaboratorInfo], Never>()
    var collaboratorPublisher: AnyPublisher<[CollaboratorInfo], Never> {
        collaboratorSubject.eraseToAnyPublisher()
    }
    #endif

    init() {
        Task {
            await setupSubscription()
        }
    }
    
    private func setupSubscription() async {
        let subscriptionID = "sharedNoteUpdates"
        let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        
        do {
            // `CKDatabase.saveSubscription(_:)` has no async overload, only the
            // completion-handler form, so it needs a continuation. Note it is
            // `save(_:)`, not `saveSubscription(_:)`: the latter was removed
            // years ago and did not compile.
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                database.save(subscription) { _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            self.subscription = subscription
        } catch {
            // Subscription might already exist
            print("CloudKit subscription setup: \(error.localizedDescription)")
        }
    }
    
    func createOrUpdate(note: Note, recordName: String? = nil) async throws -> ShareResult {
        let id = CKRecord.ID(recordName: recordName ?? note.id.uuidString)
        let record = (try? await database.record(for: id)) ?? CKRecord(recordType: "SharedNoteSnapshot", recordID: id)
        
        // Conflict resolution: use server timestamp if server version is newer
        if let serverUpdatedAt = record["updatedAt"] as? Date,
           serverUpdatedAt > note.updatedAt {
            // Server version is newer, notify caller
            #if canImport(Combine)
            syncUpdateSubject.send(SyncUpdate(
                noteID: note.id,
                title: record["title"] as? String ?? "",
                content: record["content"] as? String ?? "",
                folder: record["folder"] as? String ?? "",
                tags: (record["tags"] as? String)?.components(separatedBy: ",") ?? [],
                updatedAt: serverUpdatedAt,
                collaboratorID: record["lastEditorID"] as? String
            ))
            #endif
        }
        
        record["noteID"] = note.id.uuidString as CKRecordValue
        record["title"] = note.title as CKRecordValue
        record["content"] = note.content as CKRecordValue
        record["folder"] = note.folder as CKRecordValue
        record["tags"] = note.tags.joined(separator: ",") as CKRecordValue
        record["updatedAt"] = note.updatedAt as CKRecordValue
        record["lastEditorID"] = getCurrentUserID() as CKRecordValue
        record["editorName"] = getCurrentUserName() as CKRecordValue

        // A new share is created for a new snapshot. Existing records are
        // updated by the owner; the first share URL remains valid.
        let share = CKShare(rootRecord: record)
        share[CKShare.SystemFieldKey.title] = note.title as CKRecordValue
        share.publicPermission = .readOnly
        let saved = try await database.modifyRecords(saving: [record, share], deleting: [])
        // saveResults maps a record ID to a Result, not to the record itself.
        let savedShare: CKShare?
        if case .success(let savedRecord) = saved.saveResults[share.recordID] {
            savedShare = savedRecord as? CKShare
        } else {
            savedShare = nil
        }
        return ShareResult(recordName: record.recordID.recordName, url: savedShare?.url ?? share.url)
    }
    
    func subscribeToNoteUpdates(noteID: UUID) async throws {
        let predicate = NSPredicate(format: "noteID == %@", noteID.uuidString)
        let query = CKQuery(recordType: "SharedNoteSnapshot", predicate: predicate)
        
        let (matchResults, _) = try await database.records(matching: query)
        
        for (_, result) in matchResults {
            switch result {
            case .success(let record):
                if let title = record["title"] as? String,
                   let content = record["content"] as? String,
                   let folder = record["folder"] as? String,
                   let tagsString = record["tags"] as? String,
                   let updatedAt = record["updatedAt"] as? Date {
                    
                    #if canImport(Combine)
                    syncUpdateSubject.send(SyncUpdate(
                        noteID: noteID,
                        title: title,
                        content: content,
                        folder: folder,
                        tags: tagsString.components(separatedBy: ","),
                        updatedAt: updatedAt,
                        collaboratorID: record["lastEditorID"] as? String
                    ))
                    #endif
                }
            case .failure(let error):
                print("Error fetching record: \(error)")
            }
        }
    }
    
    func updateCollaboratorPresence(noteID: UUID, isEditing: Bool) async {
        let collaboratorID = getCurrentUserID()
        let presenceRecord = CKRecord(recordType: "CollaboratorPresence")
        presenceRecord["noteID"] = noteID.uuidString as CKRecordValue
        presenceRecord["userID"] = collaboratorID as CKRecordValue
        presenceRecord["userName"] = getCurrentUserName() as CKRecordValue
        presenceRecord["isEditing"] = isEditing as CKRecordValue
        presenceRecord["lastSeen"] = Date() as CKRecordValue
        
        do {
            try await database.save(presenceRecord)
            await refreshCollaborators(for: noteID)
        } catch {
            print("Failed to update presence: \(error)")
        }
    }
    
    private func refreshCollaborators(for noteID: UUID) async {
        // NSPredicate's format arguments must be CVarArg, and Swift's Date is
        // not. NSDate is the bridge type that is.
        let cutoff = NSDate(timeIntervalSinceNow: -300) // active in the last 5 minutes
        let predicate = NSPredicate(format: "noteID == %@ AND lastSeen > %@",
                                   noteID.uuidString,
                                   cutoff)
        let query = CKQuery(recordType: "CollaboratorPresence", predicate: predicate)
        
        do {
            let (matchResults, _) = try await database.records(matching: query)
            var collaborators: [CollaboratorInfo] = []
            
            for (_, result) in matchResults {
                switch result {
                case .success(let record):
                    if let userID = record["userID"] as? String,
                       let userName = record["userName"] as? String,
                       let lastSeen = record["lastSeen"] as? Date,
                       let isEditing = record["isEditing"] as? Bool {
                        
                        let info = CollaboratorInfo(
                            userID: userID,
                            name: userName,
                            lastSeen: lastSeen,
                            isEditing: isEditing
                        )
                        collaborators.append(info)
                        activeCollaborators[userID] = info
                    }
                case .failure:
                    break
                }
            }
            
            #if canImport(Combine)
            collaboratorSubject.send(collaborators)
            #endif
        } catch {
            print("Failed to refresh collaborators: \(error)")
        }
    }
    
    private func getCurrentUserID() -> String {
        // In a real app, this would come from CKContainer.default().fetchUserRecordID()
        // For now, use device identifier
        #if canImport(UIKit)
        return UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        #else
        return UUID().uuidString
        #endif
    }
    
    private func getCurrentUserName() -> String {
        // In a real app, this would come from user preferences or iCloud account
        return UserDefaults.standard.string(forKey: "userName") ?? "مستخدم"
    }
    
    func setUserName(_ name: String) {
        UserDefaults.standard.set(name, forKey: "userName")
    }
}
#else
/// The Windows/Linux parse target has no CloudKit SDK. Apple builds use the
/// implementation above; this keeps the package source-parsable elsewhere.
actor CloudKitCollaboration {
    static let shared = CloudKitCollaboration()
    struct ShareResult { let recordName: String; let url: URL? }
    struct CollaboratorInfo { let userID: String; let name: String; let lastSeen: Date; let isEditing: Bool }
    struct SyncUpdate { let noteID: UUID; let title: String; let content: String; let folder: String; let tags: [String]; let updatedAt: Date; let collaboratorID: String? }
    
    #if canImport(Combine)
    private let syncUpdateSubject = PassthroughSubject<SyncUpdate, Never>()
    var syncUpdatePublisher: AnyPublisher<SyncUpdate, Never> {
        syncUpdateSubject.eraseToAnyPublisher()
    }
    
    private let collaboratorSubject = PassthroughSubject<[CollaboratorInfo], Never>()
    var collaboratorPublisher: AnyPublisher<[CollaboratorInfo], Never> {
        collaboratorSubject.eraseToAnyPublisher()
    }
    #endif
    
    func createOrUpdate(note: Note, recordName: String? = nil) async throws -> ShareResult {
        throw NSError(domain: "CloudKitUnavailable", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "CloudKit متاح فقط عند البناء باستخدام Apple SDK."
        ])
    }
    
    func subscribeToNoteUpdates(noteID: UUID) async throws {
        throw NSError(domain: "CloudKitUnavailable", code: 1)
    }
    
    func updateCollaboratorPresence(noteID: UUID, isEditing: Bool) async {
        // No-op on non-Apple platforms
    }
    
    func setUserName(_ name: String) {
        // No-op on non-Apple platforms
    }
}
#endif
