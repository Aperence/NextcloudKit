//
//  NextcloudKit.swift
//  NextcloudKit
//
//  Created by Marino Faggiana on 12/10/19.
//  Copyright © 2022 Marino Faggiana. All rights reserved.
//
//  Author Marino Faggiana <marino.faggiana@nextcloud.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

#if os(macOS)
import Foundation
#else
import UIKit
#endif
import Alamofire
import SwiftyJSON

open class NextcloudKit: SessionDelegate {
    public static let shared: NextcloudKit = {
        let instance = NextcloudKit()
        return instance
    }()
    internal lazy var internalSessionManager: Alamofire.Session = {
        return Alamofire.Session(configuration: nkCommonInstance.sessionConfiguration,
                                 delegate: self,
                                 rootQueue: nkCommonInstance.rootQueue,
                                 startRequestsImmediately: true,
                                 requestQueue: nkCommonInstance.requestQueue,
                                 serializationQueue: nkCommonInstance.serializationQueue,
                                 interceptor: nil,
                                 serverTrustManager: nil,
                                 redirectHandler: nil,
                                 cachedResponseHandler: nil,
                                 eventMonitors: [AlamofireLogger(nkCommonInstance: self.nkCommonInstance)])
    }()
    public var sessionManager: Alamofire.Session {
        return internalSessionManager
    }
    #if !os(watchOS)
    private let reachabilityManager = Alamofire.NetworkReachabilityManager()
    #endif
    // private var cookies: [String:[HTTPCookie]] = [:]
    public let nkCommonInstance = NKCommon()

    override public init(fileManager: FileManager = .default) {
        super.init(fileManager: fileManager)
        #if !os(watchOS)
        startNetworkReachabilityObserver()
        #endif
    }

    deinit {
        #if !os(watchOS)
        stopNetworkReachabilityObserver()
        #endif
    }

    // MARK: - Setup

    public func setup(account: String? = nil, user: String, userId: String, password: String, urlBase: String, userAgent: String, nextcloudVersion: Int, groupIdentifier: String? = nil, delegate: NKCommonDelegate?) {
        self.setup(account: account, user: user, userId: userId, password: password, urlBase: urlBase, groupIdentifier: groupIdentifier)
        self.setup(userAgent: userAgent)
        self.setup(nextcloudVersion: nextcloudVersion)
        self.setup(delegate: delegate)
    }

    public func setup(account: String? = nil, user: String, userId: String, password: String, urlBase: String, groupIdentifier: String? = nil) {
        self.nkCommonInstance._groupIdentifier = groupIdentifier
        if (self.nkCommonInstance.account != account) || (self.nkCommonInstance.urlBase != urlBase && self.nkCommonInstance.user != user) {
            if let cookieStore = sessionManager.session.configuration.httpCookieStorage {
                for cookie in cookieStore.cookies ?? [] {
                    cookieStore.deleteCookie(cookie)
                }
            }
            self.nkCommonInstance.internalTypeIdentifiers = []
        }

        if let account {
            self.nkCommonInstance._account = account
        } else {
            self.nkCommonInstance._account = ""
        }
        self.nkCommonInstance._user = user
        self.nkCommonInstance._userId = userId
        self.nkCommonInstance._password = password
        self.nkCommonInstance._urlBase = urlBase
    }

    public func setup(delegate: NKCommonDelegate?) {
        self.nkCommonInstance.delegate = delegate
    }

    public func setup(userAgent: String) {
        self.nkCommonInstance._userAgent = userAgent
    }

    public func setup(nextcloudVersion: Int) {
        self.nkCommonInstance._nextcloudVersion = nextcloudVersion
    }

    /*
    internal func saveCookies(response : HTTPURLResponse?) {

        if let headerFields = response?.allHeaderFields as? [String : String] {
            if let url = URL(string: self.nkCommonInstance.urlBase) {
                let HTTPCookie = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
                if HTTPCookie.count > 0 {
                    cookies[self.nkCommonInstance.account] = HTTPCookie
                } else {
                    cookies[self.nkCommonInstance.account] = nil
                }
            }
        }
    }

    internal func injectsCookies() {

        if let cookies = cookies[self.nkCommonInstance.account] {
            if let url = URL(string: self.nkCommonInstance.urlBase) {
                sessionManager.session.configuration.httpCookieStorage?.setCookies(cookies, for: url, mainDocumentURL: nil)
            }
        }
    }
    */

    // MARK: - Reachability

    #if !os(watchOS)
    public func isNetworkReachable() -> Bool {
        return reachabilityManager?.isReachable ?? false
    }

    private func startNetworkReachabilityObserver() {
        reachabilityManager?.startListening(onUpdatePerforming: { status in
            switch status {
            case .unknown:
                self.nkCommonInstance.delegate?.networkReachabilityObserver(NKCommon.TypeReachability.unknown)
            case .notReachable:
                self.nkCommonInstance.delegate?.networkReachabilityObserver(NKCommon.TypeReachability.notReachable)
            case .reachable(.ethernetOrWiFi):
                self.nkCommonInstance.delegate?.networkReachabilityObserver(NKCommon.TypeReachability.reachableEthernetOrWiFi)
            case .reachable(.cellular):
                self.nkCommonInstance.delegate?.networkReachabilityObserver(NKCommon.TypeReachability.reachableCellular)
            }
        })
    }

    private func stopNetworkReachabilityObserver() {
        reachabilityManager?.stopListening()
    }
    #endif

    // MARK: - Session utility

    public func getSessionManager() -> URLSession {
       return sessionManager.session
    }

    // MARK: - download / upload

    public func download(serverUrlFileName: Any,
                         fileNameLocalPath: String,
                         account: String,
                         options: NKRequestOptions = NKRequestOptions(),
                         requestHandler: @escaping (_ request: DownloadRequest) -> Void = { _ in },
                         taskHandler: @escaping (_ task: URLSessionTask) -> Void = { _ in },
                         progressHandler: @escaping (_ progress: Progress) -> Void = { _ in },
                         completionHandler: @escaping (_ account: String, _ etag: String?, _ date: Date?, _ lenght: Int64, _ allHeaderFields: [AnyHashable: Any]?, _ afError: AFError?, _ nKError: NKError) -> Void) {
        var convertible: URLConvertible?
        if serverUrlFileName is URL {
            convertible = serverUrlFileName as? URLConvertible
        } else if serverUrlFileName is String || serverUrlFileName is NSString {
            convertible = (serverUrlFileName as? String)?.encodedToUrl
        }
        guard let url = convertible else {
            options.queue.async { completionHandler(account, nil, nil, 0, nil, nil, .urlError) }
            return
        }
        var destination: Alamofire.DownloadRequest.Destination?
        let fileNamePathLocalDestinationURL = NSURL.fileURL(withPath: fileNameLocalPath)
        let destinationFile: DownloadRequest.Destination = { _, _ in
            return (fileNamePathLocalDestinationURL, [.removePreviousFile, .createIntermediateDirectories])
        }
        destination = destinationFile
        let headers = self.nkCommonInstance.getStandardHeaders(options: options)

        let request = sessionManager.download(url, method: .get, parameters: nil, encoding: URLEncoding.default, headers: headers, interceptor: nil, to: destination).validate(statusCode: 200..<300).onURLSessionTaskCreation { task in
            task.taskDescription = options.taskDescription
            options.queue.async { taskHandler(task) }
        } .downloadProgress { progress in
            options.queue.async { progressHandler(progress) }
        } .response(queue: self.nkCommonInstance.backgroundQueue) { response in
            switch response.result {
            case .failure(let error):
                let resultError = NKError(error: error, afResponse: response, responseData: nil)
                options.queue.async { completionHandler(account, nil, nil, 0, nil, error, resultError) }
            case .success:
                var date: Date?
                var etag: String?
                var length: Int64 = 0
                let allHeaderFields = response.response?.allHeaderFields

                if let result = response.response?.allHeaderFields["Content-Length"] as? String {
                    length = Int64(result) ?? 0
                }
                if self.nkCommonInstance.findHeader("oc-etag", allHeaderFields: response.response?.allHeaderFields) != nil {
                    etag = self.nkCommonInstance.findHeader("oc-etag", allHeaderFields: response.response?.allHeaderFields)
                } else if self.nkCommonInstance.findHeader("etag", allHeaderFields: response.response?.allHeaderFields) != nil {
                    etag = self.nkCommonInstance.findHeader("etag", allHeaderFields: response.response?.allHeaderFields)
                }
                if etag != nil {
                    etag = etag?.replacingOccurrences(of: "\"", with: "")
                }
                if let dateString = self.nkCommonInstance.findHeader("Date", allHeaderFields: response.response?.allHeaderFields) {
                    date = self.nkCommonInstance.convertDate(dateString, format: "EEE, dd MMM y HH:mm:ss zzz")
                }

                options.queue.async { completionHandler(account, etag, date, length, allHeaderFields, nil, .success) }
            }
        }

        options.queue.async { requestHandler(request) }
    }

    public func upload(serverUrlFileName: Any,
                       fileNameLocalPath: String,
                       dateCreationFile: Date? = nil,
                       dateModificationFile: Date? = nil,
                       account: String,
                       options: NKRequestOptions = NKRequestOptions(),
                       requestHandler: @escaping (_ request: UploadRequest) -> Void = { _ in },
                       taskHandler: @escaping (_ task: URLSessionTask) -> Void = { _ in },
                       progressHandler: @escaping (_ progress: Progress) -> Void = { _ in },
                       completionHandler: @escaping (_ account: String, _ ocId: String?, _ etag: String?, _ date: Date?, _ size: Int64, _ allHeaderFields: [AnyHashable: Any]?, _ afError: AFError?, _ nkError: NKError) -> Void) {
        var convertible: URLConvertible?
        var size: Int64 = 0
        if serverUrlFileName is URL {
            convertible = serverUrlFileName as? URLConvertible
        } else if serverUrlFileName is String || serverUrlFileName is NSString {
            convertible = (serverUrlFileName as? String)?.encodedToUrl
        }
        guard let url = convertible else {
            options.queue.async { completionHandler(account, nil, nil, nil, 0, nil, nil, .urlError) }
            return
        }
        let fileNameLocalPathUrl = URL(fileURLWithPath: fileNameLocalPath)
        var headers = self.nkCommonInstance.getStandardHeaders(options: options)
        // Epoch of linux do not permitted negativ value
        if let dateCreationFile, dateCreationFile.timeIntervalSince1970 > 0 {
            headers.update(name: "X-OC-CTime", value: "\(dateCreationFile.timeIntervalSince1970)")
        }
        // Epoch of linux do not permitted negativ value
        if let dateModificationFile, dateModificationFile.timeIntervalSince1970 > 0 {
            headers.update(name: "X-OC-MTime", value: "\(dateModificationFile.timeIntervalSince1970)")
        }

        let request = sessionManager.upload(fileNameLocalPathUrl, to: url, method: .put, headers: headers, interceptor: nil, fileManager: .default).validate(statusCode: 200..<300).onURLSessionTaskCreation(perform: { task in
            task.taskDescription = options.taskDescription
            options.queue.async { taskHandler(task) }
        }) .uploadProgress { progress in
            options.queue.async { progressHandler(progress) }
            size = progress.totalUnitCount
        } .response(queue: self.nkCommonInstance.backgroundQueue) { response in
            switch response.result {
            case .failure(let error):
                let resultError = NKError(error: error, afResponse: response, responseData: response.data)
                options.queue.async { completionHandler(account, nil, nil, nil, 0, nil, error, resultError) }
            case .success:
                var ocId: String?, etag: String?
                let allHeaderFields = response.response?.allHeaderFields
                if self.nkCommonInstance.findHeader("oc-fileid", allHeaderFields: response.response?.allHeaderFields) != nil {
                    ocId = self.nkCommonInstance.findHeader("oc-fileid", allHeaderFields: response.response?.allHeaderFields)
                } else if self.nkCommonInstance.findHeader("fileid", allHeaderFields: response.response?.allHeaderFields) != nil {
                    ocId = self.nkCommonInstance.findHeader("fileid", allHeaderFields: response.response?.allHeaderFields)
                }
                if self.nkCommonInstance.findHeader("oc-etag", allHeaderFields: response.response?.allHeaderFields) != nil {
                    etag = self.nkCommonInstance.findHeader("oc-etag", allHeaderFields: response.response?.allHeaderFields)
                } else if self.nkCommonInstance.findHeader("etag", allHeaderFields: response.response?.allHeaderFields) != nil {
                    etag = self.nkCommonInstance.findHeader("etag", allHeaderFields: response.response?.allHeaderFields)
                }
                if etag != nil {
                    etag = etag?.replacingOccurrences(of: "\"", with: "")
                }
                if let dateString = self.nkCommonInstance.findHeader("date", allHeaderFields: response.response?.allHeaderFields) {
                    if let date = self.nkCommonInstance.convertDate(dateString, format: "EEE, dd MMM y HH:mm:ss zzz") {
                        options.queue.async { completionHandler(account, ocId, etag, date, size, allHeaderFields, nil, .success) }
                    } else {
                        options.queue.async { completionHandler(account, nil, nil, nil, 0, allHeaderFields, nil, .invalidDate) }
                    }
                } else {
                    options.queue.async { completionHandler(account, nil, nil, nil, 0, allHeaderFields, nil, .invalidDate) }
                }
            }
        }

        options.queue.async { requestHandler(request) }
    }

    /// - Parameters:
    ///     - directory: The local directory where is the file to be split
    ///     - fileName: The name of the file to be splites
    ///     - date: If exist the date of file
    ///     - creationDate: If exist the creation date of file
    ///     - serverUrl: The serverURL where the file will be deposited once reassembled
    ///     - chunkFolder: The name of temp folder, usually NSUUID().uuidString
    ///     - filesChunk: The struct it will contain all file names with the increment size  still to be sent.
    ///                Example filename: "3","4","5" .... size: 30000000, 40000000, 43000000
    ///     - chunkSizeInMB: Size in MB of chunk

    public func uploadChunk(directory: String,
                            fileName: String,
                            date: Date?,
                            creationDate: Date?,
                            serverUrl: String,
                            chunkFolder: String,
                            filesChunk: [(fileName: String, size: Int64)],
                            chunkSize: Int,
                            account: String,
                            options: NKRequestOptions = NKRequestOptions(),
                            numChunks: @escaping (_ num: Int) -> Void = { _ in },
                            counterChunk: @escaping (_ counter: Int) -> Void = { _ in },
                            start: @escaping (_ filesChunk: [(fileName: String, size: Int64)]) -> Void = { _ in },
                            requestHandler: @escaping (_ request: UploadRequest) -> Void = { _ in },
                            taskHandler: @escaping (_ task: URLSessionTask) -> Void = { _ in },
                            progressHandler: @escaping (_ totalBytesExpected: Int64, _ totalBytes: Int64, _ fractionCompleted: Double) -> Void = { _, _, _ in },
                            uploaded: @escaping (_ fileChunk: (fileName: String, size: Int64)) -> Void = { _ in },
                            completion: @escaping (_ account: String, _ filesChunk: [(fileName: String, size: Int64)]?, _ file: NKFile?, _ afError: AFError?, _ error: NKError) -> Void) {
        let userId = self.nkCommonInstance.userId
        let urlBase = self.nkCommonInstance.urlBase
        let dav = self.nkCommonInstance.dav
        let fileNameLocalSize = self.nkCommonInstance.getFileSize(filePath: directory + "/" + fileName)
        let serverUrlChunkFolder = urlBase + "/" + dav + "/uploads/" + userId + "/" + chunkFolder
        let serverUrlFileName = urlBase + "/" + dav + "/files/" + userId + self.nkCommonInstance.returnPathfromServerUrl(serverUrl) + "/" + fileName
        if options.customHeader == nil {
            options.customHeader = [:]
        }
        options.customHeader?["Destination"] = serverUrlFileName
        options.customHeader?["OC-Total-Length"] = String(fileNameLocalSize)

        // check space
        #if os(macOS)
        var fsAttributes: [FileAttributeKey: Any]
        do {
            fsAttributes = try FileManager.default.attributesOfFileSystem(forPath: "/")
        } catch {
            return completion(account, nil, nil, nil, NKError(errorCode: NKError.chunkNoEnoughMemory))
        }
        let freeDisk = ((fsAttributes[FileAttributeKey.systemFreeSize] ?? 0) as? Int64) ?? 0
        #elseif os(visionOS) || os(iOS)
        var freeDisk: Int64 = 0
        let fileURL = URL(fileURLWithPath: directory as String)
        do {
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let capacity = values.volumeAvailableCapacityForImportantUsage {
                freeDisk = capacity
            }
        } catch { }
        #endif

        #if os(visionOS) || os(iOS)
        if freeDisk < fileNameLocalSize * 4 {
            // It seems there is not enough space to send the file
            let error = NKError(errorCode: NKError.chunkNoEnoughMemory, errorDescription: "_chunk_enough_memory_")
            return completion(account, nil, nil, nil, error)
        }
        #endif

        func createFolder(completion: @escaping (_ errorCode: NKError) -> Void) {
            readFileOrFolder(serverUrlFileName: serverUrlChunkFolder, depth: "0", account: account, options: options) { _, _, _, error in
                if error == .success {
                    completion(NKError())
                } else if error.errorCode == 404 {
                    NextcloudKit.shared.createFolder(serverUrlFileName: serverUrlChunkFolder, account: account, options: options) { _, _, _, error in
                        completion(error)
                    }
                } else {
                    completion(error)
                }
            }
        }

        createFolder { error in
            guard error == .success else {
                return completion(account, nil, nil, nil, NKError(errorCode: NKError.chunkCreateFolder, errorDescription: error.errorDescription))
            }
            var uploadNKError = NKError()
            var uploadAFError: AFError?

            self.nkCommonInstance.chunkedFile(inputDirectory: directory, outputDirectory: directory, fileName: fileName, chunkSize: chunkSize, filesChunk: filesChunk) { num in
                numChunks(num)
            } counterChunk: { counter in
                counterChunk(counter)
            } completion: { filesChunk in
                if filesChunk.isEmpty {
                    // The file for sending could not be created
                    let error = NKError(errorCode: NKError.chunkFilesNull, errorDescription: "_chunk_files_null_")
                    return completion(account, nil, nil, nil, error)
                }
                var filesChunkOutput = filesChunk
                start(filesChunkOutput)

                for fileChunk in filesChunk {
                    let serverUrlFileName = serverUrlChunkFolder + "/" + fileChunk.fileName
                    let fileNameLocalPath = directory + "/" + fileChunk.fileName
                    let fileSize = self.nkCommonInstance.getFileSize(filePath: fileNameLocalPath)
                    if fileSize == 0 {
                        // The file could not be sent
                        let error = NKError(errorCode: NKError.chunkFileNull, errorDescription: "_chunk_file_null_")
                        return completion(account, nil, nil, .explicitlyCancelled, error)
                    }
                    let semaphore = DispatchSemaphore(value: 0)
                    self.upload(serverUrlFileName: serverUrlFileName, fileNameLocalPath: fileNameLocalPath, account: account, options: options, requestHandler: { request in
                        requestHandler(request)
                    }, taskHandler: { task in
                        taskHandler(task)
                    }, progressHandler: { _ in
                        let totalBytesExpected = fileNameLocalSize
                        let totalBytes = fileChunk.size
                        let fractionCompleted = Double(totalBytes) / Double(totalBytesExpected)
                        progressHandler(totalBytesExpected, totalBytes, fractionCompleted)
                    }) { _, _, _, _, _, _, afError, error in
                        if error == .success {
                            filesChunkOutput.removeFirst()
                            uploaded(fileChunk)
                        }
                        uploadAFError = afError
                        uploadNKError = error
                        semaphore.signal()
                    }
                    semaphore.wait()

                    if uploadNKError != .success {
                        break
                    }
                }

                guard uploadNKError == .success else {
                    return completion(account, filesChunkOutput, nil, uploadAFError, NKError(errorCode: NKError.chunkFileUpload, errorDescription: uploadNKError.errorDescription))
                }

                // Assemble the chunks
                let serverUrlFileNameSource = serverUrlChunkFolder + "/.file"
                // Epoch of linux do not permitted negativ value
                if let creationDate, creationDate.timeIntervalSince1970 > 0 {
                    options.customHeader?["X-OC-CTime"] = "\(creationDate.timeIntervalSince1970)"
                }
                // Epoch of linux do not permitted negativ value
                if let date, date.timeIntervalSince1970 > 0 {
                    options.customHeader?["X-OC-MTime"] = "\(date.timeIntervalSince1970)"
                }
                // Calculate Assemble Timeout
                let assembleSizeInGB = Double(fileNameLocalSize) / 1e9
                let assembleTimePerGB: Double = 3 * 60  // 3  min
                let assembleTimeMin: Double = 60        // 60 sec
                let assembleTimeMax: Double = 30 * 60   // 30 min
                options.timeout = max(assembleTimeMin, min(assembleTimePerGB * assembleSizeInGB, assembleTimeMax))

                self.moveFileOrFolder(serverUrlFileNameSource: serverUrlFileNameSource, serverUrlFileNameDestination: serverUrlFileName, overwrite: true, account: account, options: options) { _, error in
                    guard error == .success else {
                        return completion(account, filesChunkOutput, nil, nil, NKError(errorCode: NKError.chunkMoveFile, errorDescription: error.errorDescription))
                    }

                    self.readFileOrFolder(serverUrlFileName: serverUrlFileName, depth: "0", account: account, options: NKRequestOptions(queue: self.nkCommonInstance.backgroundQueue)) { _, files, _, error in

                        guard error == .success, let file = files.first else {
                            return completion(account, filesChunkOutput, nil, nil, NKError(errorCode: NKError.chunkMoveFile, errorDescription: error.errorDescription))
                        }
                        return completion(account, filesChunkOutput, file, nil, error)
                    }
                }
            }
        }
    }

    // MARK: - SessionDelegate

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if self.nkCommonInstance.delegate == nil {
            self.nkCommonInstance.writeLog("[WARNING] URLAuthenticationChallenge, no delegate found, perform with default handling")
            completionHandler(URLSession.AuthChallengeDisposition.performDefaultHandling, nil)
        } else {
            self.nkCommonInstance.delegate?.authenticationChallenge(session, didReceive: challenge, completionHandler: { authChallengeDisposition, credential in
                if self.nkCommonInstance.levelLog > 1 {
                    self.nkCommonInstance.writeLog("[INFO AUTH] Challenge Disposition: \(authChallengeDisposition.rawValue)")
                }
                completionHandler(authChallengeDisposition, credential)
            })
        }
    }
}

final class AlamofireLogger: EventMonitor {
    let nkCommonInstance: NKCommon

    init(nkCommonInstance: NKCommon) {
        self.nkCommonInstance = nkCommonInstance
    }

    func requestDidResume(_ request: Request) {
        if self.nkCommonInstance.levelLog > 0 {
            self.nkCommonInstance.writeLog("Network request started: \(request)")
            if self.nkCommonInstance.levelLog > 1 {
                let allHeaders = request.request.flatMap { $0.allHTTPHeaderFields.map { $0.description } } ?? "None"
                let body = request.request.flatMap { $0.httpBody.map { String(decoding: $0, as: UTF8.self) } } ?? "None"

                self.nkCommonInstance.writeLog("Network request headers: \(allHeaders)")
                self.nkCommonInstance.writeLog("Network request body: \(body)")
            }
        }
    }

    func request<Value>(_ request: DataRequest, didParseResponse response: AFDataResponse<Value>) {
        guard let date = self.nkCommonInstance.convertDate(Date(), format: "yyyy-MM-dd' 'HH:mm:ss") else { return }
        let responseResultString = String("\(response.result)")
        let responseDebugDescription = String("\(response.debugDescription)")
        let responseAllHeaderFields = String("\(String(describing: response.response?.allHeaderFields))")

        if self.nkCommonInstance.levelLog > 0 {
            if self.nkCommonInstance.levelLog == 1 {
                if let request = response.request {
                    let requestString = "\(request)"
                    self.nkCommonInstance.writeLog("Network response request: " + requestString + ", result: " + responseResultString)
                } else {
                    self.nkCommonInstance.writeLog("Network response result: " + responseResultString)
                }
            } else {
                self.nkCommonInstance.writeLog("Network response result: \(date) " + responseDebugDescription)
                self.nkCommonInstance.writeLog("Network response all headers: \(date) " + responseAllHeaderFields)
            }
        }
    }
}
