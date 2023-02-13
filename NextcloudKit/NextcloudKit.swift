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

import Foundation
import Alamofire
import SwiftyJSON

@objc open class NextcloudKit: SessionDelegate {
    @objc public static let shared: NextcloudKit = {
        let instance = NextcloudKit()
        return instance
    }()
            
    internal lazy var _sessionManager: Alamofire.Session = {
        let configuration = URLSessionConfiguration.af.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return Alamofire.Session(configuration: configuration, delegate: self, rootQueue: DispatchQueue(label: "com.nextcloud.nextcloudkit.sessionManagerData.rootQueue"), startRequestsImmediately: true, requestQueue: nil, serializationQueue: nil, interceptor: nil, serverTrustManager: nil, redirectHandler: nil, cachedResponseHandler: nil, eventMonitors: [AlamofireLogger(nkCommonInstance: self.nkCommonInstance)])
    }()

    public var sessionManager: Alamofire.Session {
        get {
            return _sessionManager
        }
    }
    
    private let reachabilityManager = Alamofire.NetworkReachabilityManager()
    //private var cookies: [String:[HTTPCookie]] = [:]

    @objc public let nkCommonInstance = NKCommon()
    
    override public init(fileManager: FileManager = .default) {
        super.init(fileManager: fileManager)
        startNetworkReachabilityObserver()
    }
    
    deinit {
        stopNetworkReachabilityObserver()
    }

    // MARK: - Setup

    @objc public func setup(account: String? = nil, user: String, userId: String, password: String, urlBase: String, userAgent: String, nextcloudVersion: Int, delegate: NKCommonDelegate?) {

        self.setup(account:account, user: user, userId: userId, password: password, urlBase: urlBase)
        self.setup(userAgent: userAgent)
        self.setup(nextcloudVersion: nextcloudVersion)
        self.setup(delegate: delegate)
    }

    @objc public func setup(account: String? = nil, user: String, userId: String, password: String, urlBase: String) {

        if (self.nkCommonInstance.account != account) || (self.nkCommonInstance.urlBase != urlBase && self.nkCommonInstance.user != user) {
            if let cookieStore = sessionManager.session.configuration.httpCookieStorage {
                for cookie in cookieStore.cookies ?? [] {
                    cookieStore.deleteCookie(cookie)
                }
            }
            self.nkCommonInstance.internalTypeIdentifiers = []
        }

        if let account = account {
            self.nkCommonInstance._account = account
        } else {
            self.nkCommonInstance._account = ""
        }
        self.nkCommonInstance._user = user
        self.nkCommonInstance._userId = userId
        self.nkCommonInstance._password = password
        self.nkCommonInstance._urlBase = urlBase
    }

    @objc public func setup(delegate: NKCommonDelegate?) {

        self.nkCommonInstance.delegate = delegate
    }

    @objc public func setup(userAgent: String) {

        self.nkCommonInstance._userAgent = userAgent
    }

    @objc public func setup(nextcloudVersion: Int) {

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

    //MARK: - Reachability
    
    @objc public func isNetworkReachable() -> Bool {
        return reachabilityManager?.isReachable ?? false
    }
    
    private func startNetworkReachabilityObserver() {
        
        reachabilityManager?.startListening(onUpdatePerforming: { (status) in
            switch status {

            case .unknown :
                self.nkCommonInstance.delegate?.networkReachabilityObserver?(NKCommon.typeReachability.unknown)

            case .notReachable:
                self.nkCommonInstance.delegate?.networkReachabilityObserver?(NKCommon.typeReachability.notReachable)
                
            case .reachable(.ethernetOrWiFi):
                self.nkCommonInstance.delegate?.networkReachabilityObserver?(NKCommon.typeReachability.reachableEthernetOrWiFi)

            case .reachable(.cellular):
                self.nkCommonInstance.delegate?.networkReachabilityObserver?(NKCommon.typeReachability.reachableCellular)
            }
        })
    }
    
    private func stopNetworkReachabilityObserver() {
        
        reachabilityManager?.stopListening()
    }
    
    //MARK: - Session utility
        
    @objc public func getSessionManager() -> URLSession {
       return sessionManager.session
    }
    
    /*
    //MARK: -
    
    private func makeEvents() -> [EventMonitor] {
        
        let events = ClosureEventMonitor()
        events.requestDidFinish = { request in
            print("Request finished \(request)")
        }
        events.taskDidComplete = { session, task, error in
            print("Request failed \(session) \(task) \(String(describing: error))")
            /*
            if  let urlString = (error as NSError?)?.userInfo["NSErrorFailingURLStringKey"] as? String,
                let resumedata = (error as NSError?)?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                print("Found resume data for url \(urlString)")
                //self.startDownload(urlString, resumeData: resumedata)
            }
            */
        }
        return [events]
    }
    */
    
    //MARK: - download / upload
    
    @objc public func download(serverUrlFileName: Any,
                               fileNameLocalPath: String,
                               customUserAgent: String? = nil,
                               addCustomHeaders: [String: String]? = nil,
                               queue: DispatchQueue = .main,
                               taskHandler: @escaping (_ task: URLSessionTask) -> () = { _ in },
                               progressHandler: @escaping (_ progress: Progress) -> () = { _ in },
                               completionHandler: @escaping (_ account: String, _ etag: String?, _ date: NSDate?, _ lenght: Int64, _ allHeaderFields: [AnyHashable : Any]?, _ nkError: NKError) -> Void) {
        
        download(serverUrlFileName: serverUrlFileName, fileNameLocalPath: fileNameLocalPath, customUserAgent: customUserAgent, addCustomHeaders: addCustomHeaders, queue: queue) { (request) in
            // not available in objc
        } taskHandler: { (task) in
            taskHandler(task)
        } progressHandler: { (progress) in
            progressHandler(progress)
        } completionHandler: { (account, etag, date, lenght, allHeaderFields, afError, nkError) in
            // error not available in objc
            completionHandler(account, etag, date, lenght, allHeaderFields, nkError)
        }
    }
    
    public func download(serverUrlFileName: Any,
                         fileNameLocalPath: String,
                         customUserAgent: String? = nil,
                         addCustomHeaders: [String: String]? = nil,
                         queue: DispatchQueue = .main,
                         requestHandler: @escaping (_ request: DownloadRequest) -> () = { _ in },
                         taskHandler: @escaping (_ task: URLSessionTask) -> () = { _ in },
                         progressHandler: @escaping (_ progress: Progress) -> () = { _ in },
                         completionHandler: @escaping (_ account: String, _ etag: String?, _ date: NSDate?, _ lenght: Int64, _ allHeaderFields: [AnyHashable : Any]?, _ afError: AFError?, _ nKError: NKError) -> Void) {
        
        let account = self.nkCommonInstance.account
        var convertible: URLConvertible?
        
        if serverUrlFileName is URL {
            convertible = serverUrlFileName as? URLConvertible
        } else if serverUrlFileName is String || serverUrlFileName is NSString {
            convertible = (serverUrlFileName as! String).encodedToUrl
        }
        
        guard let url = convertible else {
            queue.async { completionHandler(account, nil, nil, 0, nil, nil, .urlError) }
            return
        }
        
        var destination: Alamofire.DownloadRequest.Destination?
        let fileNamePathLocalDestinationURL = NSURL.fileURL(withPath: fileNameLocalPath)
        let destinationFile: DownloadRequest.Destination = { _, _ in
            return (fileNamePathLocalDestinationURL, [.removePreviousFile, .createIntermediateDirectories])
        }
        destination = destinationFile
        
        let headers = self.nkCommonInstance.getStandardHeaders(addCustomHeaders, customUserAgent: customUserAgent)
        
        let request = sessionManager.download(url, method: .get, parameters: nil, encoding: URLEncoding.default, headers: headers, interceptor: nil, to: destination).validate(statusCode: 200..<300).onURLSessionTaskCreation { (task) in
            
            queue.async { taskHandler(task) }
            
        } .downloadProgress { progress in
            
            queue.async { progressHandler(progress) }
            
        } .response(queue: self.nkCommonInstance.backgroundQueue) { response in
            
            switch response.result {
            case .failure(let error):
                let resultError = NKError(error: error, afResponse: response)
                queue.async { completionHandler(account, nil, nil, 0, nil, error, resultError) }
            case .success( _):

                var date: NSDate?
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
                    etag = etag!.replacingOccurrences(of: "\"", with: "")
                }
                
                if let dateString = self.nkCommonInstance.findHeader("Date", allHeaderFields: response.response?.allHeaderFields) {
                    date = self.nkCommonInstance.convertDate(dateString, format: "EEE, dd MMM y HH:mm:ss zzz")
                }
                
                queue.async { completionHandler(account, etag, date, length, allHeaderFields, nil , .success) }
            }
        }
        
        queue.async { requestHandler(request) }
    }
    
    @objc public func upload(serverUrlFileName: String,
                             fileNameLocalPath: String,
                             dateCreationFile: Date? = nil,
                             dateModificationFile: Date? = nil,
                             customUserAgent: String? = nil,
                             addCustomHeaders: [String: String]? = nil,
                             queue: DispatchQueue = .main,
                             taskHandler: @escaping (_ task: URLSessionTask) -> () = { _ in },
                             progressHandler: @escaping (_ progress: Progress) -> () = { _ in },
                             completionHandler: @escaping (_ account: String, _ ocId: String?, _ etag: String?, _ date: NSDate?, _ size: Int64, _ allHeaderFields: [AnyHashable : Any]?, _ nkError: NKError) -> Void) {
        
        upload(serverUrlFileName: serverUrlFileName, fileNameLocalPath: fileNameLocalPath, dateCreationFile: dateCreationFile, dateModificationFile: dateModificationFile, customUserAgent: customUserAgent, addCustomHeaders: addCustomHeaders, queue: queue) { (request) in
            // not available in objc
        } taskHandler: { (task) in
            taskHandler(task)
        } progressHandler: { (progress) in
            progressHandler(progress)
        } completionHandler: { (account, ocId, etag, date, size, allHeaderFields, error, nkError) in
            // error not available in objc
            completionHandler(account, ocId, etag, date, size, allHeaderFields, nkError)
        }
    }

    public func upload(serverUrlFileName: Any,
                       fileNameLocalPath: String,
                       dateCreationFile: Date? = nil,
                       dateModificationFile: Date? = nil,
                       customUserAgent: String? = nil,
                       addCustomHeaders: [String: String]? = nil,
                       queue: DispatchQueue = .main,
                       requestHandler: @escaping (_ request: UploadRequest) -> () = { _ in },
                       taskHandler: @escaping (_ task: URLSessionTask) -> () = { _ in },
                       progressHandler: @escaping (_ progress: Progress) -> () = { _ in },
                       completionHandler: @escaping (_ account: String, _ ocId: String?, _ etag: String?, _ date: NSDate?, _ size: Int64, _ allHeaderFields: [AnyHashable : Any]?, _ afError: AFError?, _ nkError: NKError) -> Void) {
        
        let account = self.nkCommonInstance.account
        var convertible: URLConvertible?
        var size: Int64 = 0

        if serverUrlFileName is URL {
            convertible = serverUrlFileName as? URLConvertible
        } else if serverUrlFileName is String || serverUrlFileName is NSString {
            convertible = (serverUrlFileName as! String).encodedToUrl
        }
        
        guard let url = convertible else {
            queue.async { completionHandler(account, nil, nil, nil, 0, nil, nil, .urlError) }
            return
        }
        
        let fileNameLocalPathUrl = URL.init(fileURLWithPath: fileNameLocalPath)
        
        var headers = self.nkCommonInstance.getStandardHeaders(addCustomHeaders, customUserAgent: customUserAgent)
        if dateCreationFile != nil {
            let sDate = "\(dateCreationFile?.timeIntervalSince1970 ?? 0)"
            headers.update(name: "X-OC-CTime", value: sDate)
        }
        if dateModificationFile != nil {
            let sDate = "\(dateModificationFile?.timeIntervalSince1970 ?? 0)"
            headers.update(name: "X-OC-MTime", value: sDate)
        }
        
        let request = sessionManager.upload(fileNameLocalPathUrl, to: url, method: .put, headers: headers, interceptor: nil, fileManager: .default).validate(statusCode: 200..<300).onURLSessionTaskCreation(perform: { (task) in
            
            queue.async { taskHandler(task) }
            
        }) .uploadProgress { progress in
            
            queue.async { progressHandler(progress) }
            size = progress.totalUnitCount
            
        } .response(queue: self.nkCommonInstance.backgroundQueue) { response in
            
            switch response.result {
            case .failure(let error):
                let resultError = NKError(error: error, afResponse: response)
                queue.async { completionHandler(account, nil, nil, nil, 0, nil, error, resultError) }
            case .success( _):
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
                
                if etag != nil { etag = etag!.replacingOccurrences(of: "\"", with: "") }
                
                if let dateString = self.nkCommonInstance.findHeader("date", allHeaderFields: response.response?.allHeaderFields) {
                    if let date = self.nkCommonInstance.convertDate(dateString, format: "EEE, dd MMM y HH:mm:ss zzz") {
                        queue.async { completionHandler(account, ocId, etag, date, size, allHeaderFields, nil, .success) }
                    } else {
                        queue.async { completionHandler(account, nil, nil, nil, 0, allHeaderFields, nil, .invalidDate) }
                    }
                } else {
                    queue.async { completionHandler(account, nil, nil, nil, 0, allHeaderFields, nil, .invalidDate) }
                }
            }
        }
        
        queue.async { requestHandler(request) }
    }
    
    //MARK: - SessionDelegate

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        
        if self.nkCommonInstance.delegate == nil {
            self.nkCommonInstance.writeLog("[WARNING] URLAuthenticationChallenge, no delegate found, perform with default handling")
            completionHandler(URLSession.AuthChallengeDisposition.performDefaultHandling, nil)
        } else {
            self.nkCommonInstance.delegate?.authenticationChallenge?(session, didReceive: challenge, completionHandler: { authChallengeDisposition, credential in
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
        let responseResultString = String.init("\(response.result)")
        let responseDebugDescription = String.init("\(response.debugDescription)")
        let responseAllHeaderFields = String.init("\(String(describing: response.response?.allHeaderFields))")
        
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
