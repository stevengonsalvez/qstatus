// ABOUTME: Fetches Copilot Enterprise quota data from the undocumented copilot_internal API.
// Impersonates VSCode to get a valid response. Auth via GitHub OAuth token.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct CopilotUsageFetcher: Sendable {
    private let token: String

    public init(oauthToken: String) {
        self.token = oauthToken
    }

    public func fetch() async throws -> CopilotUsageResponse {
        guard let url = URL(string: "https://api.github.com/copilot_internal/user") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("token \(self.token)", forHTTPHeaderField: "Authorization")
        self.addCommonHeaders(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw CopilotAuthError.unauthorized
        }

        guard httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(CopilotUsageResponse.self, from: data)
    }

    private func addCommonHeaders(to request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot-chat/0.26.7", forHTTPHeaderField: "Editor-Plugin-Version")
        request.setValue("GitHubCopilotChat/0.26.7", forHTTPHeaderField: "User-Agent")
        request.setValue("2025-04-01", forHTTPHeaderField: "X-Github-Api-Version")
    }
}

public enum CopilotAuthError: Error, LocalizedError {
    case unauthorized
    case noTokenFound

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "GitHub token is invalid or lacks Copilot access"
        case .noTokenFound:
            return "No GitHub OAuth token found in gh CLI config or Keychain"
        }
    }
}
