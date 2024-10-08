//
//  String+Extension.swift
//  NextcloudKit
//
//  Created by Marino Faggiana on 02/02/23.
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

extension String {
    public var urlEncoded: String? {
        // +        for historical reason, most web servers treat + as a replacement of whitespace
        // ?, &     mark query pararmeter which should not be part of a url string, but added seperately
        let urlAllowedCharSet = CharacterSet.urlQueryAllowed.subtracting(["+", "?", "&"])
        return addingPercentEncoding(withAllowedCharacters: urlAllowedCharSet)
    }

    public var encodedToUrl: URLConvertible? {
        return urlEncoded?.asUrl
    }

    public var asUrl: URLConvertible? {
        return try? asURL()
    }

    public var withRemovedFileExtension: String {
        return String(NSString(string: self).deletingPathExtension)
    }

    public var fileExtension: String {
        return String(NSString(string: self).pathExtension)
    }
}
