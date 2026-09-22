import SwiftUI
import AppKit

enum PIIType: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    case rfc
    case curp
    case clabe
    case cedula
    case phone
    case email
    case name
    case organization
    case address
    case identifier

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rfc: "RFC"
        case .curp: "CURP"
        case .clabe: "CLABE"
        case .cedula: "Cédula"
        case .phone: "Teléfono"
        case .email: "Correo"
        case .name: "Nombre"
        case .organization: "Empresa"
        case .address: "Domicilio"
        case .identifier: "Identificador"
        }
    }

    /// Label used inside replacement tags, e.g. `[NOMBRE 1]`, `[RFC 1]`.
    var tagLabel: String {
        switch self {
        case .rfc: "RFC"
        case .curp: "CURP"
        case .clabe: "CLABE"
        case .cedula: "CEDULA"
        case .phone: "TELEFONO"
        case .email: "CORREO"
        case .name: "NOMBRE"
        case .organization: "EMPRESA"
        case .address: "DOMICILIO"
        case .identifier: "IDENTIFICADOR"
        }
    }

    var badgeNSColor: NSColor {
        switch self {
        case .rfc: NSColor(srgbRed: 0.15, green: 0.35, blue: 0.78, alpha: 1)
        case .curp: NSColor(srgbRed: 0.42, green: 0.22, blue: 0.68, alpha: 1)
        case .clabe: NSColor(srgbRed: 0.05, green: 0.45, blue: 0.48, alpha: 1)
        case .cedula: NSColor(srgbRed: 0.62, green: 0.16, blue: 0.22, alpha: 1)
        case .phone: NSColor(srgbRed: 0.72, green: 0.32, blue: 0.06, alpha: 1)
        case .email: NSColor(srgbRed: 0.08, green: 0.42, blue: 0.58, alpha: 1)
        case .name: NSColor(srgbRed: 0.12, green: 0.48, blue: 0.26, alpha: 1)
        case .organization: NSColor(srgbRed: 0.22, green: 0.30, blue: 0.48, alpha: 1)
        case .address: NSColor(srgbRed: 0.62, green: 0.40, blue: 0.04, alpha: 1)
        case .identifier: NSColor(srgbRed: 0.32, green: 0.36, blue: 0.42, alpha: 1)
        }
    }

    var badgeBackground: Color {
        Color(nsColor: badgeNSColor)
    }
}
