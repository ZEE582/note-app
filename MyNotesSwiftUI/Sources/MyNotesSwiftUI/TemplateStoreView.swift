import SwiftUI

struct TemplateStoreView: View {
    @EnvironmentObject private var store: NotesStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var templateStore = TemplateStore()
    @State private var selectedTemplate: StudyTemplate?

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 14)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerBar
                Divider()
                if templateStore.filteredTemplates.isEmpty {
                    ScrollView {
                        EmptyStateCard(
                            title: "لا توجد قوالب مطابقة",
                            message: "جرّب فئة أخرى أو امسح عبارة البحث.",
                            icon: "square.grid.2x2",
                            actionTitle: "إعادة تعيين البحث",
                            action: resetFilters
                        )
                    }
                } else {
                    templateGrid
                }
            }
            .navigationTitle("متجر القوالب")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إغلاق") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        resetFilters()
                    } label: {
                        Label("إعادة تعيين", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(isFilterEmpty)
                }
            }
            .sheet(item: $selectedTemplate) { template in
                TemplateDetailView(template: template, templateStore: templateStore) {
                    createNote(from: template)
                }
            }
        }
    }

    // MARK: - Header

    private var isFilterEmpty: Bool {
        templateStore.selectedCategory == nil && templateStore.searchQuery.isEmpty
    }

    private func resetFilters() {
        templateStore.selectedCategory = nil
        templateStore.searchQuery = ""
    }

    private var headerBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("ابحث في العناوين والوسوم", text: $templateStore.searchQuery)
                    .textFieldStyle(.plain)
                if !templateStore.searchQuery.isEmpty {
                    Button {
                        templateStore.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(AppTheme.neutralFill, in: RoundedRectangle(cornerRadius: AppTheme.Metrics.pillRadius, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CategoryFilterButton(
                        title: "الكل",
                        symbol: "square.grid.2x2",
                        count: templateStore.templates.count,
                        isSelected: templateStore.selectedCategory == nil
                    ) {
                        templateStore.selectedCategory = nil
                    }

                    ForEach(TemplateCategory.allCases, id: \.self) { category in
                        let count = templateStore.count(in: category)
                        if count > 0 {
                            CategoryFilterButton(
                                title: category.rawValue,
                                symbol: category.icon,
                                count: count,
                                isSelected: templateStore.selectedCategory == category
                            ) {
                                templateStore.selectedCategory = templateStore.selectedCategory == category ? nil : category
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
            }
            .scrollIndicators(.hidden)

            if let message = templateStore.lastMessage {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                    Text(message)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button {
                        templateStore.clearMessage()
                    } label: {
                        Image(systemName: "xmark").font(.caption.weight(.bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(AppTheme.brandSoft, in: RoundedRectangle(cornerRadius: AppTheme.Metrics.chipRadius, style: .continuous))
                .padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - Grid

    private var templateGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(templateStore.filteredTemplates) { template in
                    TemplateCard(
                        template: template,
                        isDownloaded: templateStore.isDownloaded(template),
                        isPurchased: templateStore.isPurchased(template)
                    ) {
                        selectedTemplate = template
                    }
                }
            }
            .padding(14)
        }
    }

    // MARK: - Note creation

    /// Uses `createNote(from:)` so the template's folder, tags, sections and
    /// flashcards all survive. The earlier version looked the new note up by
    /// title and body, which could attach the wrong note's flashcards.
    private func createNote(from template: StudyTemplate) {
        let note = templateStore.createNoteFromTemplate(template)
        store.createNote(from: note)
        selectedTemplate = nil
    }
}

// MARK: - Category filter

struct CategoryFilterButton: View {
    let title: String
    let symbol: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(title)
                Text("\(count)")
                    .font(.caption2.weight(.heavy))
                    .opacity(0.7)
            }
            .font(.subheadline.weight(isSelected ? .bold : .regular))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? AppTheme.brand : AppTheme.neutralFill, in: Capsule())
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Card

struct TemplateCard: View {
    let template: StudyTemplate
    let isDownloaded: Bool
    let isPurchased: Bool
    let onTap: () -> Void

    private var accent: Color { template.category.color }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: template.category.icon)
                    .font(.title3)
                    .foregroundStyle(accent)
                    .frame(width: 38, height: 38)
                    .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.title)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(template.category.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Text(template.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            HStack(spacing: 6) {
                TagChip(text: "\(template.content.flashcards.count) بطاقة", tint: AppTheme.brand)
                if let firstTag = template.allTags.first {
                    TagChip(text: "#\(firstTag)", tint: .secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Label("\(template.downloadCount)", systemImage: "arrow.down.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Label(String(format: "%.1f", template.rating), systemImage: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                Spacer(minLength: 0)
                if template.isPremium {
                    if isPurchased {
                        Label("مفعّل", systemImage: "checkmark.seal.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.success)
                    } else {
                        HStack(spacing: 2) {
                            Image(systemName: "crown.fill").font(.caption2)
                            Text("$\(String(format: "%.2f", template.price ?? 0))")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.brandDeep)
                    }
                } else {
                    Text(isDownloaded ? "مُنزّل" : "مجاني")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isDownloaded ? AppTheme.success : .secondary)
                }
            }
        }
        .cardSurface(padding: 14)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Detail

struct TemplateDetailView: View {
    let template: StudyTemplate
    @ObservedObject var templateStore: TemplateStore
    let onCreateNote: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingPreview = false

    private var accent: Color { template.category.color }

    private var actionKind: ActionKind {
        if templateStore.isDownloaded(template) { return .createNote }
        if template.isPremium && !templateStore.isPurchased(template) { return .unlock }
        return .download
    }

    private enum ActionKind {
        case createNote, download, unlock

        var title: String {
            switch self {
            case .createNote: return "إنشاء ملاحظة من القالب"
            case .download: return "تنزيل القالب"
            case .unlock: return "تفعيل القالب"
            }
        }

        var symbol: String {
            switch self {
            case .createNote: return "doc.text"
            case .download: return "arrow.down.circle.fill"
            case .unlock: return "crown.fill"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    descriptionSection
                    contentSection
                    featuresSection
                    statsSection
                    actionButton
                    if template.isPremium && !templateStore.isPurchased(template) {
                        Text("لا يوجد متجر مدفوعات في هذه النسخة؛ التفعيل يتم محليًا دون أي عملية شراء.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                }
                .padding()
            }
            .navigationTitle("تفاصيل القالب")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إغلاق") { dismiss() }
                }
            }
            .sheet(isPresented: $showingPreview) {
                TemplatePreviewView(template: template)
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: template.category.icon)
                    .font(.largeTitle)
                    .foregroundStyle(accent)
                    .frame(width: 56, height: 56)
                    .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(template.title)
                        .font(.title2.weight(.heavy))
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        TagChip(text: template.category.rawValue, tint: accent, filled: true)
                        if template.isPremium {
                            TagChip(text: "مميز", tint: AppTheme.warning)
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            if !template.allTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(template.allTags, id: \.self) { tag in
                            TagChip(text: "#\(tag)", tint: AppTheme.brand)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeading(title: "الوصف", icon: "text.alignleft")
            Text(template.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: "محتوى القالب",
                icon: "doc.text",
                actionTitle: "معاينة كاملة",
                action: { showingPreview = true }
            )

            VStack(alignment: .leading, spacing: 10) {
                FeatureRow(icon: "text.alignleft", title: "العنوان", description: template.content.title.isEmpty ? template.title : template.content.title)
                FeatureRow(icon: "folder", title: "المجلد", description: template.content.folder)
                FeatureRow(icon: "rectangle.stack", title: "البطاقات", description: "\(template.content.flashcards.count) بطاقة جاهزة للمراجعة")
                FeatureRow(icon: "list.bullet", title: "الأقسام", description: template.content.sections.isEmpty ? "بدون أقسام" : template.content.sections.map(\.title).joined(separator: "، "))
            }
            .cardSurface(padding: 14)
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: "ما الذي يتضمنه", icon: "sparkles")
            VStack(alignment: .leading, spacing: 10) {
                FeatureRow(icon: "doc.text", title: "هيكلية منظمة", description: "أقسام وعناوين جاهزة للتنقل")
                FeatureRow(icon: "rectangle.stack", title: "\(template.content.flashcards.count) بطاقة استذكار", description: "تدخل في المراجعة فور إنشاء الملاحظة")
                FeatureRow(icon: "tag", title: "\(template.allTags.count) وسوم", description: "تصنيف تلقائي داخل المكتبة")
                FeatureRow(icon: "folder", title: "مجلد مخصص", description: "تُحفظ الملاحظة في «\(template.content.folder)»")
                if !template.content.customFields.isEmpty {
                    FeatureRow(icon: "list.clipboard", title: "حقول مخصصة", description: template.content.customFields.keys.sorted().joined(separator: "، "))
                }
            }
            .cardSurface(padding: 14)
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: "معلومات إضافية", icon: "info.circle")
            HStack(spacing: 10) {
                StatPill(icon: "arrow.down.circle", value: "\(template.downloadCount)", label: "تنزيل")
                StatPill(icon: "star.fill", value: String(format: "%.1f", template.rating), label: "التقييم", tint: .yellow)
                StatPill(icon: "person", value: template.author, label: "المؤلف", tint: .teal)
            }
            Text("الإصدار \(template.version) · اللغة \(template.language == "ar" ? "العربية" : template.language)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actionButton: some View {
        Button {
            switch actionKind {
            case .createNote:
                onCreateNote()
                dismiss()
            case .download:
                templateStore.downloadTemplate(template)
            case .unlock:
                templateStore.purchaseTemplate(template)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: actionKind.symbol)
                Text(actionKind.title)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(actionButtonGradient, in: RoundedRectangle(cornerRadius: AppTheme.Metrics.chipRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var actionButtonGradient: LinearGradient {
        switch actionKind {
        case .createNote:
            return LinearGradient(colors: [AppTheme.success, AppTheme.success.opacity(0.8)], startPoint: .top, endPoint: .bottom)
        case .unlock:
            return LinearGradient(colors: [AppTheme.warning, .orange], startPoint: .top, endPoint: .bottom)
        case .download:
            return AppTheme.brandGradient
        }
    }
}

// MARK: - Rows

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.brand)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Preview

struct TemplatePreviewView: View {
    let template: StudyTemplate
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeading(title: "المحتوى الكامل", icon: "doc.text")
                    Text(template.content.content.isEmpty ? "لا يوجد نص مبدئي لهذا القالب." : template.content.content)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(AppTheme.neutralFill, in: RoundedRectangle(cornerRadius: AppTheme.Metrics.chipRadius, style: .continuous))

                    if !template.content.sections.isEmpty {
                        SectionHeading(title: "الأقسام", icon: "list.bullet")
                        ForEach(template.content.sections.sorted { $0.order < $1.order }) { section in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(section.title).font(.subheadline.weight(.bold))
                                Text(section.content).font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardSurface(padding: 12)
                        }
                    }

                    if !template.content.flashcards.isEmpty {
                        SectionHeading(title: "بطاقات الاستذكار", icon: "rectangle.stack")
                        ForEach(Array(template.content.flashcards.enumerated()), id: \.offset) { index, card in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("س\(index + 1)")
                                        .font(.caption2.weight(.heavy))
                                        .foregroundStyle(AppTheme.brand)
                                    Text(card.front).font(.subheadline.weight(.semibold))
                                }
                                Text(card.back).font(.caption).foregroundStyle(.secondary)
                                if let category = card.category {
                                    TagChip(text: category, tint: .secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardSurface(padding: 12)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("معاينة القالب")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إغلاق") { dismiss() }
                }
            }
        }
    }
}
