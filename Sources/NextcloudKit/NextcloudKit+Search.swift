//
//  NextcloudKit+Search.swift
//  NextcloudKit
//
//  Created by Henrik Storch on 2022.
//  Copyright © 2022 Henrik Storch. All rights reserved.
//
//  Author Henrik Storch <henrik.storch@nextcloud.com>
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

public extension NextcloudKit {
    /// Available NC >= 20
    /// Search many different datasources in the cloud and combine them into one result.
    ///
    /// - Warning: Providers are requested concurrently. Not filtering will result in a high network load.
    ///
    /// - SeeAlso:
    ///  [Nextcloud Search API](https://docs.nextcloud.com/server/latest/developer_manual/digging_deeper/search.html)
    ///
    /// - Parameters:
    ///   - term: The search term
    ///   - options: Additional request options
    ///   - filter: Filter search provider that should be searched. Default is all available provider..
    ///   - update: Callback, notifying that a search provider return its result. Does not include previous results.
    ///   - completion: Callback, notifying that all search providers have been searched. The search is done. Includes all search results.
    func unifiedSearch(term: String,
                       timeout: TimeInterval = 30,
                       timeoutProvider: TimeInterval = 60,
                       account: String,
                       options: NKRequestOptions = NKRequestOptions(),
                       filter: @escaping (NKSearchProvider) -> Bool = { _ in true },
                       request: @escaping (DataRequest?) -> Void,
                       taskHandler: @escaping (_ task: URLSessionTask) -> Void = { _ in },
                       providers: @escaping (_ account: String, _ searchProviders: [NKSearchProvider]?) -> Void,
                       update: @escaping (_ account: String, _ searchResult: NKSearchResult?, _ provider: NKSearchProvider, _ error: NKError) -> Void,
                       completion: @escaping (_ account: String, _ data: Data?, _ error: NKError) -> Void) {
        let urlBase = self.nkCommonInstance.urlBase
        let endpoint = "ocs/v2.php/search/providers"
        guard let url = self.nkCommonInstance.createStandardUrl(serverUrl: urlBase, endpoint: endpoint) else {
            return completion(account, nil, .urlError)
        }
        let headers = self.nkCommonInstance.getStandardHeaders(options: options)

        let requestUnifiedSearch = sessionManager.request(url, method: .get, parameters: nil, encoding: URLEncoding.default, headers: headers, interceptor: nil).validate(statusCode: 200..<300).onURLSessionTaskCreation { task in
            task.taskDescription = options.taskDescription
            taskHandler(task)
        }.responseData(queue: self.nkCommonInstance.backgroundQueue) { response in
            if self.nkCommonInstance.levelLog > 0 {
                debugPrint(response)
            }
            switch response.result {
            case .success(let jsonData):
                let json = JSON(jsonData)
                let providerData = json["ocs"]["data"]
                guard let allProvider = NKSearchProvider.factory(jsonArray: providerData) else {
                    return completion(account, jsonData, NKError(rootJson: json, fallbackStatusCode: response.response?.statusCode))
                }
                providers(account, allProvider)

                let filteredProviders = allProvider.filter(filter)
                let group = DispatchGroup()

                for provider in filteredProviders {
                    group.enter()
                    let requestSearchProvider = self.searchProvider(provider.id, term: term, timeout: timeoutProvider, account: account, options: options) { account, partial, _, error in
                        update(account, partial, provider, error)
                        group.leave()
                    }
                    request(requestSearchProvider)
                }

                group.notify(queue: options.queue) {
                    completion(account, jsonData, .success)
                }
            case .failure(let error):
                let error = NKError(error: error, afResponse: response, responseData: response.data)
                return completion(account, nil, error)
            }
        }
        request(requestUnifiedSearch)
    }

    /// Available NC >= 20
    /// Search many different datasources in the cloud and combine them into one result.
    ///
    /// - SeeAlso:
    ///  [Nextcloud Search API](https://docs.nextcloud.com/server/latest/developer_manual/digging_deeper/search.html)
    ///
    /// - Parameters:
    ///   - id: provider id
    ///   - term: The search term
    ///   - limit: limit (pagination)
    ///   - cursor: cursor (pagination)
    ///   - options: Additional request options
    ///   - timeout: Filter search provider that should be searched. Default is all available provider..
    ///   - update: Callback, notifying that a search provider return its result. Does not include previous results.
    ///   - completion: Callback, notifying that all search results.
    func searchProvider(_ id: String,
                        term: String,
                        limit: Int? = nil,
                        cursor: Int? = nil,
                        timeout: TimeInterval = 60,
                        account: String,
                        options: NKRequestOptions = NKRequestOptions(),
                        taskHandler: @escaping (_ task: URLSessionTask) -> Void = { _ in },
                        completion: @escaping (_ account: String, NKSearchResult?, _ data: Data?, _ error: NKError) -> Void) -> DataRequest? {
        let urlBase = self.nkCommonInstance.urlBase
        guard let term = term.urlEncoded else {
            completion(account, nil, nil, .urlError)
            return nil
        }
        var endpoint = "ocs/v2.php/search/providers/\(id)/search?term=\(term)"
        if let limit = limit {
            endpoint += "&limit=\(limit)"
        }
        if let cursor = cursor {
            endpoint += "&cursor=\(cursor)"
        }
        guard let url = self.nkCommonInstance.createStandardUrl(
            serverUrl: urlBase,
            endpoint: endpoint)
        else {
            completion(account, nil, nil, .urlError)
            return nil
        }
        let headers = self.nkCommonInstance.getStandardHeaders(options: options)
        var urlRequest: URLRequest

        do {
            try urlRequest = URLRequest(url: url, method: .get, headers: headers)
            urlRequest.timeoutInterval = timeout
        } catch {
            completion(account, nil, nil, NKError(error: error))
            return nil
        }

        let requestSearchProvider = sessionManager.request(urlRequest).validate(statusCode: 200..<300).onURLSessionTaskCreation { task in
            task.taskDescription = options.taskDescription
            taskHandler(task)
        }.responseData(queue: self.nkCommonInstance.backgroundQueue) { response in
            if self.nkCommonInstance.levelLog > 0 {
                debugPrint(response)
            }
            switch response.result {
            case .success(let jsonData):
                let json = JSON(jsonData)
                let searchData = json["ocs"]["data"]
                guard let searchResult = NKSearchResult(json: searchData, id: id) else {
                    return completion(account, nil, jsonData, NKError(rootJson: json, fallbackStatusCode: response.response?.statusCode))
                }
                completion(account, searchResult, jsonData, .success)
            case .failure(let error):
                let error = NKError(error: error, afResponse: response, responseData: response.data)
                return completion(account, nil, nil, error)
            }
        }

        return requestSearchProvider
    }
}

public class NKSearchResult: NSObject {
    public let id: String
    public let name: String
    public let isPaginated: Bool
    public let entries: [NKSearchEntry]
    public let cursor: Int?

    init?(json: JSON, id: String) {
        guard let isPaginated = json["isPaginated"].bool,
              let name = json["name"].string,
              let entries = NKSearchEntry.factory(jsonArray: json["entries"])
        else { return nil }
        self.id = id
        self.cursor = json["cursor"].int
        self.name = name
        self.isPaginated = isPaginated
        self.entries = entries
    }
}

public class NKSearchEntry: NSObject {
    public let thumbnailURL: String
    public let title, subline: String
    public let resourceURL: String
    public let icon: String
    public let rounded: Bool
    public let attributes: [String: Any]?
    public var fileId: Int? {
        guard let fileAttribute = attributes?["fileId"] as? String else { return nil }
        return Int(fileAttribute)
    }
    public var filePath: String? {
        attributes?["path"] as? String
    }

    init?(json: JSON) {
        guard let thumbnailURL = json["thumbnailUrl"].string,
              let title = json["title"].string,
              let subline = json["subline"].string,
              let resourceURL = json["resourceUrl"].string,
              let icon = json["icon"].string,
              let rounded = json["rounded"].bool
        else { return nil }

        self.thumbnailURL = thumbnailURL
        self.title = title
        self.subline = subline
        self.resourceURL = resourceURL
        self.icon = icon
        self.rounded = rounded
        self.attributes = json["attributes"].dictionaryObject
    }

    static func factory(jsonArray: JSON) -> [NKSearchEntry]? {
        guard let allProvider = jsonArray.array else { return nil }
        return allProvider.compactMap(NKSearchEntry.init)
    }
}

public class NKSearchProvider: NSObject {
    public let id, name: String
    public let order: Int

    init?(json: JSON) {
        guard let id = json["id"].string,
              let name = json["name"].string,
              let order = json["order"].int
        else { return nil }
        self.id = id
        self.name = name
        self.order = order
    }

    static func factory(jsonArray: JSON) -> [NKSearchProvider]? {
        guard let allProvider = jsonArray.array else { return nil }
        return allProvider.compactMap(NKSearchProvider.init)
    }
}
