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

import Defaults
import Foundation
import Security

/// Official Spotify Web API access via OAuth 2.0 PKCE, scoped to the user's
/// Liked Songs (user-library-read / user-library-modify). Independent from
/// SpotifyAuthManager's sp_dc cookie session: Spotify rejects those web-player
/// tokens on api.spotify.com, so the like button needs a registered app token.
///
/// Coordinates SpotifyOAuthService (auth) and SpotifyLibraryAPI (calls), and
/// publishes raw state; the settings view owns all user-facing wording.
@MainActor
final class SpotifyLibraryManager: ObservableObject {
    static let shared = SpotifyLibraryManager()

    static let redirectURI = SpotifyOAuthService.redirectURI

    @Published private(set) var isAuthenticated = false
    @Published private(set) var isAuthorizing = false
    @Published private(set) var error: SpotifyLibraryError?

    private let tokenStore: SpotifyTokenStoring
    private let oauth: SpotifyOAuthService
    private let api: SpotifyLibraryAPI

    /// Use `.shared`. The injectable initializer exists for tests: a second live
    /// instance would race the first over Spotify's rotating refresh token.
    /// `authSession` defaults to nil rather than a presenter instance because a
    /// default argument is evaluated in a nonisolated context, and the presenter
    /// is main-actor bound.
    init(
        tokenStore: SpotifyTokenStoring = KeychainSpotifyTokenStore(),
        httpClient: SpotifyHTTPClient = URLSessionSpotifyHTTPClient(),
        authSession: SpotifyAuthSessionPresenting? = nil
    ) {
        self.tokenStore = tokenStore
        self.oauth = SpotifyOAuthService(
            tokenStore: tokenStore,
            httpClient: httpClient,
            authSession: authSession ?? WebAuthenticationSessionPresenter()
        )
        self.api = SpotifyLibraryAPI(tokenProvider: oauth, httpClient: httpClient)

        oauth.onTokenStateChange = { [weak self] in self?.refreshAuthenticationState() }

        // Both of these reach the Keychain, so neither can run inline here:
        // `shared` is created lazily by whoever asks for it first, and that
        // caller is usually on the main actor.
        //
        // Held rather than discarded so callers can tell when the startup work
        // has finished. Nothing in the app waits on it -- the state it settles
        // is published -- but a test that asserts on the result of the
        // migration has no other way to know it has happened, and asserting
        // straight after `init` would race it.
        startupTask = Task { [weak self] in
            await self?.migrateLegacyTokensIfNeeded()
            self?.refreshAuthenticationState()
        }
    }

    /// The Keychain work started by `init`. See the comment there.
    private(set) var startupTask: Task<Void, Never>?

    /// Waits for the startup migration and state refresh to finish.
    func waitForStartup() async {
        await startupTask?.value
    }

    /// Tokens were briefly stored in Defaults; move them into the Keychain once.
    /// The Defaults copy is only cleared once the Keychain write is confirmed,
    /// so a failed write can never lose the token.
    private func migrateLegacyTokensIfNeeded() async {
        let legacyAccessToken = Defaults[.spotifyLibraryAccessToken]
        if !legacyAccessToken.isEmpty,
           await tokenStore.write(legacyAccessToken, account: .accessToken) == errSecSuccess {
            Defaults[.spotifyLibraryAccessToken] = ""
        }
        let legacyRefreshToken = Defaults[.spotifyLibraryRefreshToken]
        if !legacyRefreshToken.isEmpty,
           await tokenStore.write(legacyRefreshToken, account: .refreshToken) == errSecSuccess {
            Defaults[.spotifyLibraryRefreshToken] = ""
        }
    }

    var configuredClientID: String {
        Defaults[.spotifyLibraryClientID].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Connect / Disconnect

    func connect() {
        error = nil
        let clientID = configuredClientID
        guard !clientID.isEmpty else {
            error = .missingClientID
            return
        }

        isAuthorizing = true
        Task {
            do {
                try await oauth.authorize(clientID: clientID)
                error = nil
            } catch SpotifyLibraryError.canceled {
                // The user closed the login window; not an error.
            } catch let authError as SpotifyLibraryError {
                error = authError
            } catch {
                self.error = .authSessionFailed(error.localizedDescription)
            }
            isAuthorizing = false
            refreshAuthenticationState()
        }
    }

    /// Spotify exposes no token revocation endpoint for PKCE apps, so deleting
    /// the local pair is the whole of what disconnecting can do. Users revoke
    /// the app itself at spotify.com/account/apps.
    func disconnect() {
        oauth.clearTokens()
        Defaults[.spotifyLibraryAccessToken] = ""
        Defaults[.spotifyLibraryRefreshToken] = ""
        error = nil
        // `clearTokens` deletes off the main actor, so the refresh below could
        // still read the old token. Publish the disconnected state directly.
        isAuthenticated = false
    }

    // MARK: - Saved Tracks

    /// nil = unknown (not connected / request failed)
    func isTrackSaved(trackID: String) async -> Bool? {
        await api.isTrackSaved(trackID: trackID)
    }

    func setTrackSaved(_ saved: Bool, trackID: String) async -> Bool {
        await api.setTrackSaved(saved, trackID: trackID)
    }

    // MARK: - State

    /// Republishes `isAuthenticated` from the Keychain. The read happens off
    /// the main actor, so the value lands a beat later than the call.
    private func refreshAuthenticationState() {
        let store = tokenStore
        let hasClientID = !configuredClientID.isEmpty
        Task { [weak self] in
            let hasRefreshToken = !(await store.read(.refreshToken) ?? "").isEmpty
            self?.isAuthenticated = hasRefreshToken && hasClientID
        }
    }
}
