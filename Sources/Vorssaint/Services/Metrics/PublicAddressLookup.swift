// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Darwin
import Foundation

/// The address the internet sees, asked of the speed test's own Cloudflare host
/// and only when the user presses the button: nothing but the request itself is
/// sent, and the answer is kept in memory for the connection it was read on.
final class PublicAddressLookup: NSObject, ObservableObject {
    static let shared = PublicAddressLookup()

    enum Phase: Equatable {
        case idle, loading, failed
        case loaded(String)
    }

    @Published private(set) var phase: Phase = .idle

    /// The trace page is a few hundred bytes; anything far larger is not it.
    static let maximumBytes = 4_096
    private static let endpoint = URL(string: "https://speed.cloudflare.com/cdn-cgi/trace")!

    private var session: URLSession!
    private var task: URLSessionDataTask?
    private var generation = 0
    /// The local addresses the answer was read on; see `forgetIfNetworkChanged`.
    private var network: [String] = []

    init(configuration: URLSessionConfiguration = .ephemeral) {
        super.init()
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 10
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    var isLoading: Bool { phase == .loading }

    var address: String? {
        if case .loaded(let address) = phase { return address }
        return nil
    }

    /// Main thread only. A newer lookup replaces one still in flight.
    func refresh(network: [String]) {
        task?.cancel()
        generation += 1
        let generation = self.generation
        self.network = network
        phase = .loading
        let task = session.dataTask(with: Self.endpoint) { [weak self] data, response, error in
            let address = error == nil && Self.isSuccessful(response) ? data.flatMap(Self.address(from:)) : nil
            DispatchQueue.main.async {
                guard let self, self.generation == generation else { return }
                self.task = nil
                self.phase = address.map(Phase.loaded) ?? .failed
            }
        }
        self.task = task
        task.resume()
    }

    /// A different set of local addresses means a different connection, and
    /// an address read on the previous one would now be wrong.
    func forgetIfNetworkChanged(_ current: [String]) {
        guard phase != .idle, current != network else { return }
        cancel()
    }

    func cancel() {
        task?.cancel()
        task = nil
        generation += 1
        phase = .idle
    }

    /// The `ip=` line of Cloudflare's trace page, accepted only as a literal
    /// IPv4 or IPv6 address.
    static func address(from data: Data) -> String? {
        guard data.count <= maximumBytes, let text = String(data: data, encoding: .utf8) else { return nil }
        guard let line = text.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("ip=") })
        else { return nil }
        let value = String(line.dropFirst(3))
        return isIPAddress(value) ? value : nil
    }

    static func isIPAddress(_ value: String) -> Bool {
        var v4 = in_addr()
        var v6 = in6_addr()
        return inet_pton(AF_INET, value, &v4) == 1 || inet_pton(AF_INET6, value, &v6) == 1
    }

    private static func isSuccessful(_ response: URLResponse?) -> Bool {
        guard let response = response as? HTTPURLResponse else { return false }
        return (200...299).contains(response.statusCode)
    }
}

extension PublicAddressLookup: URLSessionTaskDelegate {
    /// A redirect would carry the request to a host the privacy notes do not name.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
