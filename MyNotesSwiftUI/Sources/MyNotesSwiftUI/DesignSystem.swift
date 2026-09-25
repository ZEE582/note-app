import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Palette

/// A single, shared visual language for the whole app. Every colour, radius and
/// spacing value used by the library, the editor, the template store and the
/// flashcard review comes from here so the three surfaces cannot drift apart.
enum AppTheme {

    // MARK: Brand

    static let brand = Color(red: 0.424, green: 0.388, blue: 1.0)
    static let brandDeep = Color(red: 0.302, green: 0.271, blue: 0.827)
    static let brandSoft = Color(red: 0.910, green: 0.902, blue: 1.0)
    static let brandGradient = LinearGradient(
        colors: [brand, brandDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: Semantic

    static let success = Color(red: 0.204, green: 0.639, blue: 0.325)
    static let warning = Color(red: 0.902, green: 0.588, blue: 0.114)
    static let danger = Color(red: 0.847, green: 0.302, blue: 0.357)
    static let neutralFill = Color.primary.opacity(0.06)

    /// The accent bar colour used on note cards. Notes are grouped visually by
    /// folder so the library reads as a set of shelves instead of a flat list.
    static func accent(for folder: String) -> Color {
        let palette: [Color] = [brand, .indigo, .teal, .orange, .pink, .green, .purple, .mint]
        let index = abs(folder.hashValue) % palette.count
        return palette[index]
    }

    // MARK: Metrics

    enum Metrics {
        static let cardRadius: CGFloat = 18
        static let chipRadius: CGFloat = 9
        static let pillRadius: CGFloat = 14
        static let sectionSpacing: CGFloat = 18
        static let cardPadding: CGFloat = 16
    }
}

// MARK: - Shared modifiers

struct CardSurface: ViewModifier {
    var padding: CGFloat = AppTheme.Metrics.cardPadding
    var radius: CGFloat = AppTheme.Metrics.cardRadius

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}

extension View {
    func cardSurface(padding: CGFloat = AppTheme.Metrics.cardPadding, radius: CGFloat = AppTheme.Metrics.cardRadius) -> some View {
        modifier(CardSurface(padding: padding, radius: radius))
    }
}

// MARK: - Small components

struct TagChip: View {
    let text: String
    var tint: Color = AppTheme.brand
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(filled ? tint : tint.opacity(0.14), in: Capsule())
            .foregroundStyle(filled ? .white : tint)
    }
}

struct StatPill: View {
    let icon: String
    let value: String
    let label: String
    var tint: Color = AppTheme.brand

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.heavy))
                    .monospacedDigit()
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: AppTheme.Metrics.chipRadius, style: .continuous))
    }
}

struct SectionHeading: View {
    let title: String
    var icon: String?
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.brand)
            }
            Text(title)
                .font(.headline)
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.brand)
            }
        }
    }
}

/// Shown instead of a bare `ContentUnavailableView` so the empty state also
/// explains why it is empty and offers the obvious next action.
struct EmptyStateCard: View {
    let title: String
    let message: String
    let icon: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(AppTheme.brand)
                .frame(width: 76, height: 76)
                .background(AppTheme.brandSoft, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            Text(title)
                .font(.title3.weight(.heavy))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: "plus")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(AppTheme.brandGradient, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 20)
    }
}

// MARK: - Formatting

enum Clipboard {
    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
    }
}

enum Formatters {
    private static let locale = Locale(identifier: "ar_SA")

    /// "الآن" / "قبل ٣ ساعات" style relative stamps used across the library.
    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    static func medium(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    static func count(_ value: Int) -> String {
        value == 0 ? "لا عناصر"
            : value == 1 ? "عنصر واحد"
            : value == 2 ? "عنصران"
            : value <= 10 ? "\(value) عناصر"
            : "\(value) عنصرًا"
    }
}
