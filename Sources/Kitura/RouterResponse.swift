/**
 * Copyright IBM Corporation 2016
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **/

import KituraNet
import KituraSys

// For JSON parsing support
import SwiftyJSON

import Foundation
import LoggerAPI

// MARK: RouterResponse

public class RouterResponse {

    ///
    /// The server response
    ///
    let response: ServerResponse

    ///
    /// The router
    ///
    weak var router: Router?

    ///
    /// The associated request
    ///
    let request: RouterRequest

    ///
    /// The buffer used for output
    ///
    private let buffer = BufferList()

    ///
    /// Whether the response has ended
    ///
    var invokedEnd = false

    //
    // Current pre-flush lifecycle handler
    //
    private var preFlush: PreFlushLifecycleHandler = {request, response in }

    ///
    /// Set of cookies to return with the response
    ///
    public var cookies = [String: NSHTTPCookie]()

    ///
    /// Optional error value
    ///
    public var error: ErrorProtocol?
    
    public var headers: Headers {
        
        get {
            return response.headers
        }
        
        set(value) {
            response.headers = value
        }
    }

    ///
    /// Initializes a RouterResponse instance
    ///
    /// - Parameter response: the server response
    ///
    /// - Returns: a ServerResponse instance
    ///
    init(response: ServerResponse, router: Router, request: RouterRequest) {

        self.response = response
        self.router = router
        self.request = request
        status(HttpStatusCode.NOT_FOUND)
    }

    ///
    /// Ends the response
    ///
    /// - Throws: ???
    /// - Returns: a RouterResponse instance
    ///
    public func end() throws -> RouterResponse {

        preFlush(request: request, response: self)

        if  let data = buffer.data {
            let contentLength = headers.get("Content-Length")
            if  contentLength == nil {
                headers.set("Content-Length", value: String(buffer.count))
            }
            addCookies()

            if  request.method != .Head {
                try response.write(from: data)
            }
        }
        invokedEnd = true
        try response.end()
        return self
    }

    //
    // Add Set-Cookie headers
    //
    private func addCookies() {
        var cookieStrings = [String]()

        for  (_, cookie) in cookies {
            var cookieString = cookie.name + "=" + cookie.value + "; path=" + cookie.path + "; domain=" + cookie.domain
            if  let expiresDate = cookie.expiresDate {
                cookieString += "; expires=" + SpiUtils.httpDate(expiresDate)
            }
#if os(Linux)
            let isSecure = cookie.secure
#else
            let isSecure = cookie.isSecure
#endif
            if  isSecure  {
                cookieString += "; secure; HttpOnly"
            }

            cookieStrings.append(cookieString)
        }
        headers.set("Set-Cookie", value: cookieStrings)
    }

    ///
    /// Ends the response and sends a string
    ///
    /// - Parameter str: the String before the response ends
    ///
    /// - Throws: ???
    /// - Returns: a RouterResponse instance
    ///
    public func end(str: String) throws -> RouterResponse {

        send(str)
        try end()
        return self

    }

    ///
    /// Ends the response and sends data
    ///
    /// - Parameter data: the data to send before the response ends
    ///
    /// - Throws: ???
    /// - Returns: a RouterResponse instance
    ///
    public func end(data: NSData) throws -> RouterResponse {

        sendData(data)
        try end()
        return self

    }

    ///
    /// Sends a string
    ///
    /// - Parameter str: the string to send
    ///
    /// - Returns: a RouterResponse instance
    ///
    public func send(str: String) -> RouterResponse {

        if  let data = StringUtils.toUtf8String(str) {
            buffer.appendData(data)
        }
        return self

    }

    ///
    /// Sends data
    ///
    /// - Parameter data: the data to send
    ///
    /// - Returns: a RouterResponse instance
    ///
    public func sendData(data: NSData) -> RouterResponse {

        buffer.appendData(data)
        return self

    }

    ///
    /// Sends a file
    ///
    /// - Parameter fileName: the name of the file to send.
    ///
    /// - Returns: a RouterResponse instance
    ///
    /// Note: Sets the Content-Type header based on the "extension" of the file
    ///       If the fileName is relative, it is relative to the current directory
    ///
    public func sendFile(fileName: String) throws -> RouterResponse {
        let data = try NSData(contentsOfFile: fileName, options: [])

        let contentType =  ContentType.sharedInstance.contentTypeForFile(fileName)
        if  let contentType = contentType {
            headers.set("Content-Type", value: contentType)
        }

        buffer.appendData(data)

        return self
    }

    ///
    /// Sends JSON
    ///
    /// - Parameter json: the JSON object to send
    ///
    /// - Returns: a RouterResponse instance
    ///
    public func sendJson(json: JSON) -> RouterResponse {

        let jsonStr = json.description
        type("json")
        send(jsonStr)
        return self

    }

    ///
    /// Set the status code
    ///
    /// - Parameter status: the status code integer
    ///
    /// - Returns: a RouterResponse instance
    ///
    public func status(status: Int) -> RouterResponse {
        response.status = status
        return self
    }

    ///
    /// Set the status code
    ///
    /// - Parameter status: the status code object
    ///
    /// - Returns: a RouterResponse instance
    ///
    public func status(status: HttpStatusCode) -> RouterResponse {
        response.statusCode = status
        return self
    }

    ///
    /// Get the status code as an integer
    ///
    /// - Returns: The currently set status code as an integer
    ///
    public func getStatus() -> Int {
        return response.status
    }

    ///
    /// Get the status code as an HttpStatusCode
    ///
    /// - Returns: The currently set status code as an HttpStatusCode
    ///
    public func getStatusCode() -> HttpStatusCode {
        return response.statusCode ?? .UNKNOWN
    }

    ///
    /// Sends the status code
    ///
    /// - Parameter status: the status code integer
    ///
    /// - Throws: ???
    /// - Returns: a RouterResponse instance
    ///
    public func sendStatus(status: Int) throws -> RouterResponse {

        self.status(status)
        if  let statusText = Http.statusCodes[status] {
            send(statusText)
        } else {
            send(String(status))
        }
        return self

    }

    ///
    /// Sends the status code
    ///
    /// - Parameter status: the status code object
    ///
    /// - Throws: ???
    /// - Returns: a RouterResponse instance
    ///
    public func sendStatus(status: HttpStatusCode) throws -> RouterResponse {

        self.status(status)
        send(Http.statusCodes[status.rawValue]!)
        return self

    }

    ///
    /// Redirect to path
    ///
    /// - Parameter: the path for the redirect
    ///
    /// - Returns: a RouterResponse instance
    ///
    public func redirect(path: String) throws -> RouterResponse {
        return try redirect(.MOVED_TEMPORARILY, path: path)
    }

    ///
    /// Redirect to path with status code
    ///
    /// - Parameter: the status code for the redirect
    /// - Parameter: the path for the redirect
    ///
    /// - Returns: a RouterResponse instance
    ///
    public func redirect(status: HttpStatusCode, path: String) throws -> RouterResponse {

        try redirect(status.rawValue, path: path)
        return self

    }

    ///
    /// Redirect to path with status code
    ///
    /// - Parameter: the status code for the redirect
    /// - Parameter: the path for the redirect
    ///
    /// - Returns: a RouterResponse instance
    ///
    public func redirect(status: Int, path: String) throws -> RouterResponse {

        try self.status(status).location(path).end()
        return self

    }

    ///
    /// Sets the location path
    ///
    /// - Parameter path: the path
    ///
    /// - Returns: a RouterResponse instance
    ///
    public func location(path: String) -> RouterResponse {

        var p = path
        if  p == "back" {
            let referrer = headers.get("referrer")
            if  let r = referrer?.first {
                p = r
            } else {
                p = "/"
            }
        }
        headers.set("Location", value: p)
        return self

    }

    ///
    /// Renders a resource using Router's template engine
    ///
    /// - Parameter resource: the resource name without extension
    ///
    /// - Returns: a RouterResponse instance
    ///
    // influenced by http://expressjs.com/en/4x/api.html#app.render
    public func render(resource: String, context: [ String: Any]) throws -> RouterResponse {
        guard let router = router else {
            throw InternalError.NilVariable(variable: "router")
        }
        let renderedResource = try router.render(resource, context: context)
        return send(renderedResource)
    }

    ///
    /// Sets the Content-Type HTTP header
    ///
    /// - Parameter type: the type to set to
    ///
    public func type(type: String, charset: String? = nil) {
        if  let contentType = ContentType.sharedInstance.contentTypeForExtension(type) {
            var contentCharset = ""
            if let charset = charset {
                contentCharset = "; charset=\(charset)"
            }
            headers.set("Content-Type", value:  contentType + contentCharset)
        }
    }

    ///
    /// Sets the Content-Disposition to "attachment" and optionally
    /// sets filename parameter in Content-Disposition and Content-Type
    ///
    /// - Parameter filePath: the file to set the filename to
    ///
    public func attachment(filePath: String? = nil) {
        guard let filePath = filePath else {
            headers.set("Content-Disposition", value: "attachment")
            return
        }

        let filePaths = filePath.characters.split {$0 == "/"}.map(String.init)
        let fileName = filePaths.last
        headers.set("Content-Disposition", value: "attachment; fileName = \"\(fileName!)\"")

        let contentType =  ContentType.sharedInstance.contentTypeForFile(fileName!)
        if  let contentType = contentType {
            headers.set("Content-Type", value: contentType)
        }
    }

    ///
    /// Sets headers and attaches file for downloading
    ///
    /// - Parameter filePath: the file to download
    ///
    public func download(filePath: String) throws {
        try sendFile(filePath)
        attachment(filePath)
    }

    ///
    /// Sets the pre-flush lifecycle handler and returns the previous one
    ///
    /// - Parameter newPreFlush: The new pre-flush lifecycle handler
    public func setPreFlushHandler(newPreFlush: PreFlushLifecycleHandler) -> PreFlushLifecycleHandler {
        let oldPreFlush = preFlush
        preFlush = newPreFlush
        return oldPreFlush
    }
}

///
/// Type alias for "Before flush" (i.e. before headers and body are written) lifecycle handler
public typealias PreFlushLifecycleHandler = (request: RouterRequest, response: RouterResponse) -> Void
