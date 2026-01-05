// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Native Swift type to represent semantics of HTTP status codes.
///
/// See [RFC 2616](https://www.ietf.org/rfc/rfc2616.txt) for further information.
///
enum HTTPStatus: Int, RawRepresentable, CustomStringConvertible {
    ///
    /// Equals the raw status code of `100`.
    ///
    case `continue` = 100

    ///
    /// Equals the raw status code of `101`.
    ///
    case switchingProtocols = 101

    ///
    /// Equals the raw status code of `200`.
    ///
    case ok = 200

    ///
    /// Equals the raw status code of `201`.
    ///
    case created = 201

    ///
    /// Equals the raw status code of `202`.
    ///
    case accepted = 202

    ///
    /// Equals the raw status code of `203`.
    ///
    case nonAuthoritativeInformation = 203

    ///
    /// Equals the raw status code of `204`.
    ///
    case noContent = 204

    ///
    /// Equals the raw status code of `206`.
    ///
    case partialContent = 206

    ///
    /// Equals the raw status code of `207`.
    ///
    case multiStatus = 207

    ///
    /// Equals the raw status code of `300`.
    ///
    case multipleChoices = 300

    ///
    /// Equals the raw status code of `301`.
    ///
    case movedPermanently = 301

    ///
    /// Equals the raw status code of `302`.
    ///
    case found = 302

    ///
    /// Equals the raw status code of `303`.
    ///
    case seeOther = 303

    ///
    /// Equals the raw status code of `304`.
    ///
    case notModified = 304

    ///
    /// Equals the raw status code of `305`.
    ///
    case useProxy = 305

    ///
    /// Equals the raw status code of `307`.
    ///
    case temporaryRedirect = 307

    ///
    /// Equals the raw status code of `308`.
    ///
    case permanentRedirect = 308

    ///
    /// Equals the raw status code of `400`.
    ///
    case badRequest = 400

    ///
    /// Equals the raw status code of `401`.
    ///
    case unauthorized = 401

    ///
    /// Equals the raw status code of `402`.
    ///
    case paymentRequired = 402

    ///
    /// Equals the raw status code of `403`.
    ///
    case forbidden = 403

    ///
    /// Equals the raw status code of `404`.
    ///
    case notFound = 404

    ///
    /// Equals the raw status code of `405`.
    ///
    case methodNotAllowed = 405

    ///
    /// Equals the raw status code of `406`.
    ///
    case notAcceptable = 406

    ///
    /// Equals the raw status code of `407`.
    ///
    case proxyAuthenticationRequired = 407

    ///
    /// Equals the raw status code of `408`.
    ///
    case requestTimeout = 408

    ///
    /// Equals the raw status code of `409`.
    ///
    case conflict = 409

    ///
    /// Equals the raw status code of `410`.
    ///
    case gone = 410

    ///
    /// Equals the raw status code of `411`.
    ///
    case lengthRequired = 411

    ///
    /// Equals the raw status code of `412`.
    ///
    case preconditionFailed = 412

    ///
    /// Equals the raw status code of `413`.
    ///
    case payloadTooLarge = 413

    ///
    /// Equals the raw status code of `414`.
    ///
    case uriTooLong = 414

    ///
    /// Equals the raw status code of `415`.
    ///
    case unsupportedMediaType = 415

    ///
    /// Equals the raw status code of `416`.
    ///
    case rangeNotSatisfiable = 416

    ///
    /// Equals the raw status code of `417`.
    ///
    case expectationFailed = 417

    ///
    /// Equals the raw status code of `500`.
    ///
    case internalServerError = 500

    ///
    /// Equals the raw status code of `501`.
    ///
    case notImplemented = 501

    ///
    /// Equals the raw status code of `502`.
    ///
    case badGateway = 502

    ///
    /// Equals the raw status code of `503`.
    ///
    case serviceUnavailable = 503

    ///
    /// Equals the raw status code of `504`.
    ///
    case gatewayTimeOut = 504

    ///
    /// Equals the raw status code of `505`.
    ///
    case httpVersionNotSupported = 505

    ///
    /// Human readable description to be rendered in text.
    ///
    var description: String {
        switch self {
            case .continue:
                "Continue"
            case .switchingProtocols:
                "Switching protocols"
            case .ok:
                "OK"
            case .created:
                "Created"
            case .accepted:
                "Accepted"
            case .nonAuthoritativeInformation:
                "Non-authoritative information"
            case .noContent:
                "No content"
            case .partialContent:
                "Partial content"
            case .multiStatus:
                "Multi-status"
            case .multipleChoices:
                "Multiple choices"
            case .movedPermanently:
                "Moved permanently"
            case .found:
                "Found"
            case .seeOther:
                "See other"
            case .notModified:
                "Not modified"
            case .useProxy:
                "Use proxy"
            case .temporaryRedirect:
                "Temporary redirect"
            case .permanentRedirect:
                "Permanent redirect"
            case .badRequest:
                "Bad request"
            case .unauthorized:
                "Unauthorized"
            case .paymentRequired:
                "Payment required"
            case .forbidden:
                "Forbidden"
            case .notFound:
                "Not found"
            case .methodNotAllowed:
                "Method not allowed"
            case .notAcceptable:
                "Not acceptable"
            case .proxyAuthenticationRequired:
                "Proxy authentication requred"
            case .requestTimeout:
                "Request time-out"
            case .conflict:
                "Conflict"
            case .gone:
                "Gone"
            case .lengthRequired:
                "Length required"
            case .preconditionFailed:
                "Precondition failed"
            case .payloadTooLarge:
                "Payload too large"
            case .uriTooLong:
                "Request-URI too large"
            case .unsupportedMediaType:
                "Unsupported media type"
            case .rangeNotSatisfiable:
                "Requested range not satisfiable"
            case .expectationFailed:
                "Expectation failed"
            case .internalServerError:
                "Internal server error"
            case .notImplemented:
                "Not implemented"
            case .badGateway:
                "Bad gateway"
            case .serviceUnavailable:
                "Service unavailable"
            case .gatewayTimeOut:
                "Gateway time-out"
            case .httpVersionNotSupported:
                "HTTP version not supported"
        }
    }

    ///
    /// Whether the status code is in the range from 100 to 199.
    ///
    var isInformal: Bool {
        self.rawValue >= 100 && self.rawValue < 200
    }

    ///
    /// Whether the status code is in the range from 200 to 299.
    ///
    var isSuccess: Bool {
        self.rawValue >= 200 && self.rawValue < 300
    }

    ///
    /// Whether the status code is in the range from 300 to 399.
    ///
    var isRedirection: Bool {
        self.rawValue >= 300 && self.rawValue < 400
    }

    ///
    /// Whether the status code is in the range from 400 to 499.
    ///
    var isClientError: Bool {
        self.rawValue >= 400 && self.rawValue < 500
    }

    ///
    /// Whether the status code is in the range from 500 to 599.
    ///
    var isServerError: Bool {
        self.rawValue >= 500 && self.rawValue < 600
    }
}
