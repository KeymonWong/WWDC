//
//  TranscriptIndexer.swift
//  WWDC
//
//  Created by Guilherme Rambo on 27/05/17.
//  Copyright © 2017 Guilherme Rambo. All rights reserved.
//

import Cocoa
import RealmSwift
import SwiftyJSON

extension Notification.Name {
    public static let TranscriptIndexingDidStart = Notification.Name("io.wwdc.app.TranscriptIndexingDidStartNotification")
    public static let TranscriptIndexingDidStop = Notification.Name("io.wwdc.app.TranscriptIndexingDidStopNotification")
}

public final class TranscriptIndexer {
    
    private let storage: Storage
    
    public init(_ storage: Storage) {
        self.storage = storage
    }
    
    /// The progress when the transcripts are being downloaded/indexed
    public var transcriptIndexingProgress: Progress?
    
    private let asciiWWDCURL = "http://asciiwwdc.com/"
    
    fileprivate let bgThread = DispatchQueue.global(qos: .utility)
    
    fileprivate lazy var backgroundOperationQueue: OperationQueue = {
        let q = OperationQueue()
        
        q.underlyingQueue = self.bgThread
        q.name = "Transcript Indexing"
        
        return q
    }()
    
    /// Try to download transcripts for sessions that don't have transcripts yet
    public func downloadTranscriptsIfNeeded() {
        
        let transcriptedSessions = storage.realm.objects(Session.self).filter("year > 2012 AND transcript == nil AND SUBQUERY(assets, $asset, $asset.rawAssetType == %@).@count > 0", SessionAssetType.streamingVideo.rawValue)
        
        let sessionKeys: [String] = transcriptedSessions.map({ $0.identifier })
        
        self.indexTranscriptsForSessionsWithKeys(sessionKeys)
    }
    
    func indexTranscriptsForSessionsWithKeys(_ sessionKeys: [String]) {
        guard sessionKeys.count > 0 else { return }
        
        transcriptIndexingProgress = Progress(totalUnitCount: Int64(sessionKeys.count))
        
        for key in sessionKeys {
            guard let session = storage.realm.object(ofType: Session.self, forPrimaryKey: key) else { return }
            
            guard session.transcript == nil else { continue }
            
            indexTranscript(for: session.number, in: session.year, primaryKey: key)
        }
    }
    
    fileprivate var downloadedTranscripts: [Transcript] = []
    
    fileprivate func indexTranscript(for sessionNumber: String, in year: Int, primaryKey: String) {
        guard let url = URL(string: "\(asciiWWDCURL)\(year)//sessions/\(sessionNumber)") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let task = URLSession.shared.dataTask(with: request) { [unowned self] data, response, error in
            guard let jsonData = data else {
                self.transcriptIndexingProgress?.completedUnitCount += 1
                self.checkForCompletion()
                
                NSLog("No data returned from ASCIIWWDC for \(primaryKey)")
                
                return
            }
            
            self.backgroundOperationQueue.addOperation {
                defer {
                    self.transcriptIndexingProgress?.completedUnitCount += 1
                    
                    self.checkForCompletion()
                }
                
                let result = TranscriptsJSONAdapter().adapt(JSON(data: jsonData))
                
                guard case .success(let transcript) = result else {
                    NSLog("Error parsing transcript for \(primaryKey)")
                    return
                }
                
                DispatchQueue.main.sync {
                    self.downloadedTranscripts.append(transcript)
                }
            }
        }
        
        task.resume()
    }
    
    private func checkForCompletion() {
        guard let progress = self.transcriptIndexingProgress else { return }
        
        #if DEBUG
            NSLog("Completed: \(progress.completedUnitCount) Total: \(progress.totalUnitCount)")
        #endif
        
        if progress.completedUnitCount >= progress.totalUnitCount - 1 {
            DispatchQueue.main.async {
                #if DEBUG
                    NSLog("Transcript indexing finished")
                #endif
                
                self.storeDownloadedTranscripts()
            }
        }
    }
    
    private var isStoring = false
    
    private func storeDownloadedTranscripts() {
        guard !isStoring else { return }
        isStoring = true
        
        DispatchQueue.main.async {
            DistributedNotificationCenter.default().post(name: .TranscriptIndexingDidStart, object: nil)
        }
        
        self.backgroundOperationQueue.addOperation { [unowned self] in
            guard let realm = try? Realm(configuration: self.storage.realmConfig) else { return }
            
            realm.beginWrite()
            
            self.downloadedTranscripts.forEach { transcript in
                guard let session = realm.object(ofType: Session.self, forPrimaryKey: transcript.identifier) else {
                    NSLog("Session not found for \(transcript.identifier)")
                    return
                }
                
                session.transcript = transcript
                
                realm.add(transcript)
            }
            
            self.downloadedTranscripts.removeAll()
            
            do {
                try realm.commitWrite()
                
                DispatchQueue.main.async {
                    DistributedNotificationCenter.default().post(name: .TranscriptIndexingDidStop, object: nil)
                }
            } catch {
                NSLog("Error writing indexed transcripts to storage: \(error)")
            }
        }
    }
    
}
