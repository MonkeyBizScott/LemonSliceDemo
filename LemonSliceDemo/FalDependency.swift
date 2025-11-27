//
//  FalDependency.swift
//
//  Created by Scott on 11/27/25.
//

import Dependencies
import DependenciesMacros
import Foundation
import FalClient
import IdentifiedCollections

// MARK: Interface

@DependencyClient
struct FalDependency: Sendable {
    /// Starts an image generation job for the given input and returns an async stream
    /// of `QueueStatus` values emitted by Fal's subscription API.
    var generateImage: (String) async throws -> AsyncThrowingStream<JobStream, any Error> = { _ in
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
    var cancelCurrentJob: () async -> Void = {}
}

// MARK: Live

@available(iOSApplicationExtension, unavailable)
extension FalDependency: DependencyKey {
    // Map Interface to live methods
    public static let liveValue : Self = {
        
        return Self(
            generateImage: { input in
                try await generateImage(input: input)
            },
            cancelCurrentJob: {
                await FalActor.shared.cancelRequest()
            }
        )
    }()
    
    private static func generateImage(input: String) async throws -> AsyncThrowingStream<JobStream, any Error> {
        return try await FalActor.shared.generateImage(for: input)
    }
}

// MARK: TestKey

extension DependencyValues {
    var falDependency: FalDependency {
        get { self[FalDependency.self] }
        set { self[FalDependency.self] = newValue }
    }
}

// MARK: Preview Implementation

extension FalDependency {
    static let noop = Self(
        generateImage: { _ in
            AsyncThrowingStream { continuation in
                continuation.finish()
            }
        },
        cancelCurrentJob: {}
    )
}

struct JobStream: Identifiable, Sendable {
    let id: String
    let status: QueueStatus
    let result: FalImageResult?
}

//Verified types in QueueStatus are Sendable
extension QueueStatus: @unchecked @retroactive Sendable {}

// MARK: - Image result decoding

/// Strongly-typed representation of the image payload returned by Fal.
///
/// Expected JSON shape:
/// {
///   "images": [
///     {
///       "file_name": "nano-banana-t2i-output.png",
///       "content_type": "image/png",
///       "url": "https://..."
///     }
///   ],
///   "description": "..."
/// }
struct FalImageResult: Decodable, Sendable {
    let images: [FalImage]
    let description: String
    
    struct FalImage: Decodable, Sendable, Identifiable, Equatable {
        /// Use the image URL as a stable, unique identifier.
        var id: URL { url }
        let fileName: String
        let contentType: String
        let url: URL
        
        enum CodingKeys: String, CodingKey {
            case fileName = "file_name"
            case contentType = "content_type"
            case url
            // `id` is intentionally omitted so it is ignored by decoding/encoding.
        }
    }
}

extension Payload {
    /// Decodes the Fal image result payload into a strongly-typed `FalImageResult`.
    ///
    /// This assumes the underlying `Payload` represents a dictionary payload
    /// with the structure documented in `FalImageResult`.
    func decodeFalImageResult() throws -> FalImageResult {
        enum DecodeError: Error {
            case invalidRoot
            case missingImages
            case invalidImages
            case invalidImageItem
            case invalidURL(String)
        }
        
        // Root should be a dictionary payload
        guard case let .dict(root) = self else {
            throw DecodeError.invalidRoot
        }
        
        // Extract images array
        guard let imagesPayload = root["images"] else {
            throw DecodeError.missingImages
        }
        guard case let .array(imageArray) = imagesPayload else {
            throw DecodeError.invalidImages
        }
        
        let images: [FalImageResult.FalImage] = try imageArray.map { imagePayload in
            guard case let .dict(imageDict) = imagePayload else {
                throw DecodeError.invalidImageItem
            }
            
            // Required fields
            guard case let .string(urlString) = imageDict["url"],
                  let url = URL(string: urlString) else {
                throw DecodeError.invalidURL(String(describing: imageDict["url"]))
            }
            guard case let .string(fileName) = imageDict["file_name"] else {
                throw DecodeError.invalidImageItem
            }
            guard case let .string(contentType) = imageDict["content_type"] else {
                throw DecodeError.invalidImageItem
            }
            
            return FalImageResult.FalImage(
                fileName: fileName,
                contentType: contentType,
                url: url
            )
        }
        
        // Description is optional; default to empty string if absent or not a string
        let description: String
        if let descPayload = root["description"], case let .string(desc) = descPayload {
            description = desc
        } else {
            description = ""
        }
        
        return FalImageResult(images: images, description: description)
    }
}

final actor FalActor {
    static let shared = FalActor()
    let fal = FalClient.withCredentials(.keyPair("f1b4c4d9-6b44-4407-a8ab-f68d14a02645:f76f5aaeea6a80ae8a687fc7b48121ff"))
    var continuation: AsyncThrowingStream<JobStream, any Error>.Continuation?
    

    /// Starts a Fal image generation job and returns an async stream of its queue status
    /// using Fal's subscription API.
    /// - Parameter input: Prompt text to generate an image for.
    /// - Returns: An `AsyncThrowingStream` that yields `QueueStatus` updates until the
    ///   subscription completes or an error is thrown.
    func generateImage(for input: String) async throws -> AsyncThrowingStream<JobStream, any Error> {
        AsyncThrowingStream { continuation in
            self.continuation = continuation
            let task = Task {
                do {
                    let payload: Payload = try await fal.subscribe(
                        to: "fal-ai/nano-banana-pro",
                        input: [
                            "prompt": input
                        ],
                        includeLogs: true
                    ) { update in
                        let stream: JobStream = .init(id: input,
                                                      status: update,
                                                      result: nil)
                        continuation.yield(stream)
                    }
                    
                    
                    let result = try payload.decodeFalImageResult()
                    let stream: JobStream = .init(id: input,
                                                status: .completed(logs: [], responseUrl: ""),
                                                result: result)
                    continuation.yield(stream)
                    // Subscription finished successfully (job completed)
                    continuation.finish()
                } catch {
                    // Propagate any error to the stream consumer
                    continuation.finish(throwing: error)
                }
            }
            
            // If the consumer cancels the stream, cancel the underlying subscription task.
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
    
    func cancelRequest() {
        self.continuation?.finish()
    }
}
