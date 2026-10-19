
import Foundation

/// `GET /api/ping/` response.
public struct PingResponse: Decodable, Sendable, Equatable {
    public var response: String?
    public var user: String?
    public var version: String?
    public var taUpdate: Bool?

    enum CodingKeys: String, CodingKey {
        case response
        case user
        case version
        case taUpdate = "ta_update"
    }

    public init(response: String?, user: String?, version: String?, taUpdate: Bool?) {
        self.response = response
        self.user = user
        self.version = version
        self.taUpdate = taUpdate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        response = try? container.decodeIfPresent(String.self, forKey: .response)
        user = container.decodeFlexibleStringIfPresent(forKey: .user)
        version = try? container.decodeIfPresent(String.self, forKey: .version)
        taUpdate = container.decodeFlexibleBoolIfPresent(forKey: .taUpdate)
    }

    public var isPong: Bool { response?.lowercased() == "pong" }
}

/// `GET /api/appsettings/token/` response.
public struct TokenResponse: Decodable, Sendable, Equatable {
    public var token: String?

    enum CodingKeys: String, CodingKey {
        case token
    }

    public init(token: String?) {
        self.token = token
    }
}

/// `GET /api/user/account/` response — current user info.
public struct Account: Decodable, Sendable, Equatable {
    public var id: Int?
    public var username: String?
    public var isStaff: Bool?
    public var isSuperuser: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case name // alternate spelling seen on some DRF user serializers
        case isStaff = "is_staff"
        case isSuperuser = "is_superuser"
    }

    public init(id: Int?, username: String?, isStaff: Bool?, isSuperuser: Bool?) {
        self.id = id
        self.username = username
        self.isStaff = isStaff
        self.isSuperuser = isSuperuser
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeFlexibleIntIfPresent(forKey: .id)
        username = container.decodeFlexibleStringIfPresent(forKey: .username)
            ?? container.decodeFlexibleStringIfPresent(forKey: .name)
        isStaff = container.decodeFlexibleBoolIfPresent(forKey: .isStaff)
        isSuperuser = container.decodeFlexibleBoolIfPresent(forKey: .isSuperuser)
    }
}

/// Body for `POST /api/user/login/`.
struct LoginRequestBody: Encodable, Sendable {
    var username: String
    var password: String
    var rememberMe: String = "on"

    enum CodingKeys: String, CodingKey {
        case username
        case password
        case rememberMe = "remember_me"
    }
}
