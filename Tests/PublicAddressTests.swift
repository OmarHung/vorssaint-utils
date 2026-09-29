// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum PublicAddressTests {
    static func run(_ suite: TestSuite) {
        parsing(suite)
        lookups(suite)
    }

    private static func parsing(_ suite: TestSuite) {
        func parse(_ text: String) -> String? { PublicAddressLookup.address(from: Data(text.utf8)) }
        suite.expect(parse("fl=1\nh=speed.cloudflare.com\nip=203.0.113.9\nts=1\n") == "203.0.113.9",
                     "the ip line of the trace page is read as the public address")
        suite.expect(parse("h=x\r\nip=2001:db8::1\r\nts=1\r\n") == "2001:db8::1",
                     "an IPv6 answer with CRLF line endings is read too")
        suite.expect(parse("h=x\nts=1\n") == nil, "a page without an ip line gives no address")
        suite.expect(parse("ip=999.1.1.1\n") == nil, "an out of range IPv4 value is refused")
        suite.expect(parse("ip=<b>1.2.3.4</b>\n") == nil, "markup around the value is refused")
        suite.expect(parse("ip= 203.0.113.9\n") == nil, "a value with stray whitespace is refused")
        suite.expect(parse("clientip=203.0.113.9\n") == nil, "only the ip key itself is read")
        let padded = "ip=203.0.113.9\n" + String(repeating: "x", count: PublicAddressLookup.maximumBytes)
        suite.expect(parse(padded) == nil, "a body far larger than the trace page is refused")
    }

    private static func lookups(_ suite: TestSuite) {
        let loaded = lookup("success", suite: suite)
        suite.expect(loaded.phase == .loaded("203.0.113.9") && loaded.address == "203.0.113.9",
                     "a successful answer shows the public address")

        loaded.forgetIfNetworkChanged(["192.168.1.2 (Wi-Fi)"])
        suite.expect(loaded.phase == .loaded("203.0.113.9"),
                     "the answer is kept while the connection is the same")
        loaded.forgetIfNetworkChanged(["10.0.0.4 (Ethernet)"])
        suite.expect(loaded.phase == .idle && loaded.address == nil,
                     "a different connection forgets the address read on the previous one")

        suite.expect(lookup("unavailable", suite: suite).phase == .failed,
                     "an error status is reported as a failed check, not as an address")
        suite.expect(lookup("not-an-address", suite: suite).phase == .failed,
                     "a successful status without a valid address is a failed check")

        let redirected = lookup("redirect", suite: suite)
        suite.expect(redirected.phase == .failed, "a redirect is not followed to another host")
        suite.expect(!PublicAddressProtocol.requestedHosts(for: "redirect").contains("example.com"),
                     "the redirect target is never requested")

        let cancelled = PublicAddressLookup(configuration: configuration("slow"))
        cancelled.refresh(network: ["192.168.1.2 (Wi-Fi)"])
        suite.expect(cancelled.isLoading, "a check shows as loading until it is answered")
        cancelled.cancel()
        waitForRequest("slow")
        drainMainQueue(for: 0.3)
        suite.expect(cancelled.phase == .idle, "a cancelled check never publishes its late answer")
    }

    private static func lookup(_ scenario: String, suite: TestSuite) -> PublicAddressLookup {
        let lookup = PublicAddressLookup(configuration: configuration(scenario))
        lookup.refresh(network: ["192.168.1.2 (Wi-Fi)"])
        let deadline = Date().addingTimeInterval(3)
        while lookup.isLoading && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        suite.expect(!lookup.isLoading, "public address check \(scenario) finishes")
        return lookup
    }

    private static func configuration(_ scenario: String) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PublicAddressProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Test-Scenario": scenario]
        return configuration
    }

    private static func waitForRequest(_ scenario: String) {
        let deadline = Date().addingTimeInterval(3)
        while PublicAddressProtocol.requestedHosts(for: scenario).isEmpty && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    private static func drainMainQueue(for interval: TimeInterval) {
        let deadline = Date().addingTimeInterval(interval)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }
}

private final class PublicAddressProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var hosts: [String: [String]] = [:]

    static func requestedHosts(for scenario: String) -> [String] {
        lock.withLock { hosts[scenario] ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let scenario = request.value(forHTTPHeaderField: "X-Test-Scenario") ?? ""
        let url = request.url!
        Self.lock.withLock { Self.hosts[scenario, default: []].append(url.host ?? "") }
        switch scenario {
        case "success":
            respond(200, body: "fl=1\nh=speed.cloudflare.com\nip=203.0.113.9\nts=1\n")
        case "unavailable":
            respond(503, body: "ip=203.0.113.9\n")
        case "not-an-address":
            respond(200, body: "ip=unknown\n")
        case "redirect":
            let target = URL(string: "https://example.com/cdn-cgi/trace")!
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1",
                                           headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            respond(302, body: "ip=203.0.113.9\n")
        case "slow":
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                self.respond(200, body: "ip=203.0.113.9\n")
            }
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
        }
    }

    override func stopLoading() {}

    private func respond(_ status: Int, body: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/plain"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
