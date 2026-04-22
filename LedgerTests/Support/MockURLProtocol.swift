import Foundation

final class MockURLProtocol: URLProtocol {
    struct CapturedRequest {
        let request: URLRequest
        let body: Data?
    }

    struct Response {
        let statusCode: Int
        let headers: [String: String]
        let body: Data

        init(
            statusCode: Int,
            headers: [String: String] = [:],
            body: Data
        ) {
            self.statusCode = statusCode
            self.headers = headers
            self.body = body
        }
    }

    private static let lock = NSLock()
    private static var queuedResponses: [Response] = []
    private(set) static var capturedRequests: [CapturedRequest] = []

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        queuedResponses.removeAll()
        capturedRequests.removeAll()
    }

    static func enqueue(_ response: Response) {
        lock.lock()
        defer { lock.unlock() }
        queuedResponses.append(response)
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.capturedRequests.append(
            CapturedRequest(
                request: request,
                body: Self.bodyData(for: request)
            )
        )
        guard !Self.queuedResponses.isEmpty else {
            Self.lock.unlock()
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let response = Self.queuedResponses.removeFirst()
        Self.lock.unlock()

        let httpResponse = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )!

        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func bodyData(for request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        return readBody(from: stream)
    }

    private static func readBody(from stream: InputStream) -> Data? {
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while stream.hasBytesAvailable {
            let readCount = stream.read(&buffer, maxLength: buffer.count)
            if readCount < 0 {
                return data.isEmpty ? nil : data
            }

            if readCount == 0 {
                break
            }

            data.append(buffer, count: readCount)
        }

        return data
    }
}
