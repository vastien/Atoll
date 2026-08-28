/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import Security

enum SpotifyTokenAccount: String {
    case accessToken = "spotify-library-access-token"
    case refreshToken = "spotify-library-refresh-token"
}

/// Serialises Keychain access, and keeps it off the main actor.
///
/// `SecItemCopyMatching` and its siblings are synchronous round trips to
/// `securityd`. When the calling binary's code signature does not match the
/// ACL recorded on an item -- the normal state of any locally built copy,
/// whose cdhash differs from the one the item was written under -- they do not
/// return until the user answers a Keychain prompt. Run on the main actor that
/// stalls every main-queue hop in the app, including the ones that prompt's own
/// window needs, so the app appears frozen rather than merely waiting.
@globalActor
actor SpotifyKeychainActor {
    static let shared = SpotifyKeychainActor()

    /// Runs a synchronous Keychain call on this actor's executor.
    static func run<T: Sendable>(_ body: @Sendable @escaping () -> T) async -> T {
        await shared.perform(body)
    }

    private func perform<T: Sendable>(_ body: @Sendable () -> T) -> T {
        body()
    }
}

protocol SpotifyTokenStoring: Sendable {
    func read(_ account: SpotifyTokenAccount) async -> String?
    /// Returns the Keychain status; `errSecSuccess` means the value is stored.
    /// Callers that then discard the source (e.g. the Defaults migration) must
    /// check this before dropping the only remaining copy of the token.
    @discardableResult func write(_ value: String, account: SpotifyTokenAccount) async -> OSStatus
    @discardableResult func delete(_ account: SpotifyTokenAccount) async -> OSStatus
}

/// Keychain-backed storage for the OAuth token pair. The client ID and token
/// expiration are not secrets and stay in Defaults.
///
/// Every entry point hops onto `SpotifyKeychainActor` before touching the
/// Keychain; nothing here may be called synchronously from the main actor.
struct KeychainSpotifyTokenStore: SpotifyTokenStoring {
    private static let service = "com.Ebullioscopic.Atoll.SpotifyLibrary"

    private static func baseQuery(for account: SpotifyTokenAccount) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue
        ]
    }

    func read(_ account: SpotifyTokenAccount) async -> String? {
        await SpotifyKeychainActor.run { Self.readSync(account) }
    }

    @discardableResult
    func write(_ value: String, account: SpotifyTokenAccount) async -> OSStatus {
        await SpotifyKeychainActor.run { Self.writeSync(value, account: account) }
    }

    @discardableResult
    func delete(_ account: SpotifyTokenAccount) async -> OSStatus {
        await SpotifyKeychainActor.run { Self.deleteSync(account) }
    }

    // MARK: - Keychain

    private static func readSync(_ account: SpotifyTokenAccount) -> String? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeSync(_ value: String, account: SpotifyTokenAccount) -> OSStatus {
        let data = Data(value.utf8)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery(for: account) as CFDictionary, update as CFDictionary)
        guard status == errSecItemNotFound else {
            return status
        }
        var attributes = baseQuery(for: account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    private static func deleteSync(_ account: SpotifyTokenAccount) -> OSStatus {
        let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
        // Nothing stored is a successful end state for a delete.
        return status == errSecItemNotFound ? errSecSuccess : status
    }
}
