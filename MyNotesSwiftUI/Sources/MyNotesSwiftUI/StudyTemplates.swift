import Foundation
import SwiftUI

// MARK: - Template Models

struct StudyTemplate: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    let description: String
    let category: TemplateCategory
    let isPremium: Bool
    let price: Double?
    let content: TemplateContent
    let previewImage: String?
    let downloadCount: Int
    let rating: Double
    let author: String
    let tags: [String]
    let language: String
    let version: String
    let createdAt: Date
    let updatedAt: Date
    
    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        category: TemplateCategory,
        isPremium: Bool = false,
        price: Double? = nil,
        content: TemplateContent,
        previewImage: String? = nil,
        downloadCount: Int = 0,
        rating: Double = 0.0,
        author: String = "MyNotes",
        tags: [String] = [],
        language: String = "ar",
        version: String = "1.0"
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.category = category
        self.isPremium = isPremium
        self.price = price
        self.content = content
        self.previewImage = previewImage
        self.downloadCount = downloadCount
        self.rating = rating
        self.author = author
        self.tags = tags
        self.language = language
        self.version = version
        self.createdAt = .now
        self.updatedAt = .now
    }

    /// Templates in the bundled catalogue declare their keywords inside
    /// `content.tags`, while user-supplied ones use `tags`. Searching and
    /// display go through this union so neither set is invisible.
    var allTags: [String] {
        var seen = Set<String>()
        return (tags + content.tags).filter { seen.insert($0).inserted }
    }
}

enum TemplateCategory: String, CaseIterable, Codable {
    case programming = "برمجة"
    case mathematics = "رياضيات"
    case medicine = "طب"
    case science = "علوم"
    case business = "أعمال"
    case language = "لغات"
    case arts = "فنون"
    case general = "عام"
    
    var icon: String {
        switch self {
        case .programming: return "chevron.left.forwardslash.chevron.right"
        case .mathematics: return "function"
        case .medicine: return "cross.case"
        case .science: return "flask"
        case .business: return "briefcase"
        case .language: return "textformat"
        case .arts: return "paintbrush"
        case .general: return "doc"
        }
    }
    
    var color: Color {
        switch self {
        case .programming: return .blue
        case .mathematics: return .purple
        case .medicine: return .red
        case .science: return .green
        case .business: return .orange
        case .language: return .yellow
        case .arts: return .pink
        case .general: return .gray
        }
    }
}

struct TemplateContent: Codable, Hashable {
    let title: String
    let folder: String
    let tags: [String]
    let content: String
    let flashcards: [FlashcardTemplate]
    let sections: [TemplateSection]
    let customFields: [String: String]
    
    init(
        title: String = "",
        folder: String = "الدراسة",
        tags: [String] = [],
        content: String = "",
        flashcards: [FlashcardTemplate] = [],
        sections: [TemplateSection] = [],
        customFields: [String: String] = [:]
    ) {
        self.title = title
        self.folder = folder
        self.tags = tags
        self.content = content
        self.flashcards = flashcards
        self.sections = sections
        self.customFields = customFields
    }
}

struct FlashcardTemplate: Codable, Hashable {
    let front: String
    let back: String
    let category: String?
    
    init(front: String, back: String, category: String? = nil) {
        self.front = front
        self.back = back
        self.category = category
    }
}

struct TemplateSection: Codable, Hashable, Identifiable {
    let id: UUID
    let title: String
    let content: String
    let order: Int
    
    init(id: UUID = UUID(), title: String, content: String, order: Int = 0) {
        self.id = id
        self.title = title
        self.content = content
        self.order = order
    }
}

// MARK: - Template Store

@MainActor
class TemplateStore: ObservableObject {
    @Published private(set) var templates: [StudyTemplate] = []
    @Published private(set) var downloadedTemplates: [UUID] = []
    @Published private(set) var purchasedTemplates: [UUID] = []
    @Published var selectedCategory: TemplateCategory?
    @Published var searchQuery: String = ""
    /// Explains the outcome of the last download/purchase action so the store
    /// view can tell the user *why* nothing happened instead of silently
    /// returning. There is no payment backend in this build, so premium
    /// templates unlock locally and the UI says so plainly.
    @Published private(set) var lastMessage: String?

    private let userDefaults = UserDefaults.standard
    private let downloadedKey = "downloadedTemplates"
    private let purchasedKey = "purchasedTemplates"

    init() {
        loadUserState()
        loadTemplates()
    }

    // MARK: - Public Methods

    var filteredTemplates: [StudyTemplate] {
        var filtered = templates

        if let category = selectedCategory {
            filtered = filtered.filter { $0.category == category }
        }

        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            filtered = filtered.filter { template in
                template.title.lowercased().contains(query) ||
                template.description.lowercased().contains(query) ||
                template.category.rawValue.lowercased().contains(query) ||
                template.allTags.contains { $0.lowercased().contains(query) }
            }
        }

        return filtered.sorted { lhs, rhs in
            if lhs.isPremium != rhs.isPremium { return !lhs.isPremium }
            if lhs.downloadCount != rhs.downloadCount { return lhs.downloadCount > rhs.downloadCount }
            return lhs.title < rhs.title
        }
    }

    var popularTemplates: [StudyTemplate] {
        Array(templates.sorted { $0.downloadCount > $1.downloadCount }.prefix(10))
    }

    var freeTemplates: [StudyTemplate] {
        templates.filter { !$0.isPremium }
    }

    var premiumTemplates: [StudyTemplate] {
        templates.filter(\.isPremium)
    }

    func count(in category: TemplateCategory) -> Int {
        templates.filter { $0.category == category }.count
    }

    @discardableResult
    func downloadTemplate(_ template: StudyTemplate) -> Bool {
        guard !downloadedTemplates.contains(template.id) else {
            lastMessage = "«\(template.title)» مُنزّل مسبقًا."
            return true
        }

        if template.isPremium && !purchasedTemplates.contains(template.id) {
            lastMessage = "هذا قالب مدفوع. افتحه ثم فعّله من الزر الذهبي."
            return false
        }

        downloadedTemplates.append(template.id)
        saveUserState()
        bumpDownloadCount(for: template)
        lastMessage = "تم تنزيل «\(template.title)». يمكنك الآن إنشاء ملاحظة منه."
        return true
    }

    @discardableResult
    func purchaseTemplate(_ template: StudyTemplate) -> Bool {
        guard template.isPremium else {
            lastMessage = "هذا القالب مجاني."
            return downloadTemplate(template)
        }
        guard !purchasedTemplates.contains(template.id) else {
            return downloadTemplate(template)
        }

        // No StoreKit backend ships with this build. The unlock is recorded
        // locally so the rest of the app behaves as if it were owned; the
        // detail view states plainly that there is no payment step.
        purchasedTemplates.append(template.id)
        saveUserState()
        // Download first, then report: `downloadTemplate` sets its own message
        // and would otherwise overwrite the "just unlocked" wording.
        downloadTemplate(template)
        lastMessage = "تم تفعيل «\(template.title)» وتنزيله. يمكنك الآن إنشاء ملاحظة منه."
        return true
    }

    func isDownloaded(_ template: StudyTemplate) -> Bool {
        downloadedTemplates.contains(template.id)
    }

    func isPurchased(_ template: StudyTemplate) -> Bool {
        purchasedTemplates.contains(template.id)
    }

    func clearMessage() {
        lastMessage = nil
    }

    /// Builds a ready-to-save note. Tags, folders and flashcards are all
    /// carried over, so handing the result to `NotesStore.createNote(from:)`
    /// keeps the whole template instead of just its title and body.
    func createNoteFromTemplate(_ template: StudyTemplate) -> Note {
        let content = template.content
        let sectionsContent = template.content.sections
            .sorted { $0.order < $1.order }
            .map { "## \($0.title)\n\n\($0.content)\n\n" }
            .joined()

        let fullContent = content.content.isEmpty
            ? sectionsContent
            : content.content + (sectionsContent.isEmpty ? "" : "\n\n" + sectionsContent)

        var note = Note(
            title: content.title.isEmpty ? template.title : content.title,
            content: fullContent,
            folder: content.folder.isEmpty ? "الدراسة" : content.folder,
            tags: content.tags.isEmpty ? template.allTags : content.tags
        )

        note.flashcards = content.flashcards.map { card in
            Flashcard(front: card.front, back: card.back)
        }

        if !content.customFields.isEmpty {
            note.content += "\n\n---\n\n"
            for key in content.customFields.keys.sorted() {
                note.content += "- **\(key):** \(content.customFields[key] ?? "")\n"
            }
        }

        return note
    }

    // MARK: - Private Methods

    private func bumpDownloadCount(for template: StudyTemplate) {
        guard let index = templates.firstIndex(where: { $0.id == template.id }) else { return }
        templates[index] = StudyTemplate(
            id: template.id,
            title: template.title,
            description: template.description,
            category: template.category,
            isPremium: template.isPremium,
            price: template.price,
            content: template.content,
            previewImage: template.previewImage,
            downloadCount: template.downloadCount + 1,
            rating: template.rating,
            author: template.author,
            tags: template.tags,
            language: template.language,
            version: template.version
        )
    }
    
    private func loadUserState() {
        if let downloadedData = userDefaults.data(forKey: downloadedKey),
           let downloaded = try? JSONDecoder().decode([UUID].self, from: downloadedData) {
            downloadedTemplates = downloaded
        }
        
        if let purchasedData = userDefaults.data(forKey: purchasedKey),
           let purchased = try? JSONDecoder().decode([UUID].self, from: purchasedData) {
            purchasedTemplates = purchased
        }
    }
    
    private func saveUserState() {
        if let downloadedData = try? JSONEncoder().encode(downloadedTemplates) {
            userDefaults.set(downloadedData, forKey: downloadedKey)
        }
        
        if let purchasedData = try? JSONEncoder().encode(purchasedTemplates) {
            userDefaults.set(purchasedData, forKey: purchasedKey)
        }
    }
    
    private func loadTemplates() {
        templates = SampleTemplates.all
    }
}

// MARK: - Sample Templates

struct SampleTemplates {
    static let all: [StudyTemplate] = [
        // Programming Templates
        StudyTemplate(
            title: "تخطيط مشروع برمجي",
            description: "قالب شامل لتخطيط وتوثيق المشاريع البرمجية مع هيكلية مناسبة للمطورين",
            category: .programming,
            content: TemplateContent(
                title: "تخطيط مشروع برمجي",
                folder: "برمجة",
                tags: ["برمجة", "تطوير", "مشروع"],
                content: """
                ## نظرة عامة على المشروع
                
                **اسم المشروع:** [أدخل اسم المشروع]
                **الوصف:** [وصف مختصر للمشروع وأهدافه]
                **تاريخ البدء:** [التاريخ]
                **تاريخ الانتهاء المستهدف:** [التاريخ]
                
                ## التقنيات المستخدمة
                
                - اللغة الرئيسية: [مثال: Swift, Python, JavaScript]
                - الإطار العمل: [مثال: SwiftUI, Django, React]
                - قاعدة البيانات: [مثال: SQLite, PostgreSQL, Firebase]
                - أدوات أخرى: [مثال: Git, Docker, CI/CD]
                
                ## هيكلية المشروع
                
                ### المكونات الرئيسية
                1. [المكون الأول - وصف وظيفته]
                2. [المكون الثاني - وصف وظيفته]
                3. [المكون الثالث - وصف وظيفه]
                
                ### المخطط الزمني
                | المرحلة | المدة | الحالة |
                |---------|-------|---------|
                | التخطيط | أسبوعين | ⏳ |
                | التطوير | شهر | ⏳ |
                | الاختبار | أسبوع | ⏳ |
                | النشر | يوم | ⏳ |
                
                ## نقاط التقنية
                
                ### المتطلبات الوظيفية
                - [ ] المتطلب الأول
                - [ ] المتطلب الثاني
                - [ ] المتطلب الثالث
                
                ### التحديات المتوقعة
                1. [التحدي الأول والحل المقترح]
                2. [التحدي الثاني والحل المقترح]
                
                ## الموارد والمراجع
                - [رابط التوثيق الرسمي]
                - [رابط المصادر التعليمية]
                - [ملاحظات إضافية]
                """,
                flashcards: [
                    FlashcardTemplate(front: "ما هو الغرض الرئيسي من المشروع؟", back: "الغرض الرئيسي هو [أدخل الإجابة]"),
                    FlashcardTemplate(front: "ما هي التقنيات الرئيسية المستخدمة؟", back: "التقنيات الرئيسية هي [أدخل الإجابة]"),
                    FlashcardTemplate(front: "ما هي التحديات المتوقعة؟", back: "التحديات المتوقعة تشمل [أدخل الإجابة]")
                ],
                sections: [
                    TemplateSection(title: "المتطلبات", content: "سجل المتطلبات التفصيلية هنا", order: 1),
                    TemplateSection(title: "تصميم الواجهة", content: "مخططات واجهة المستخدم", order: 2),
                    TemplateSection(title: "قاعدة البيانات", content: "هيكلية البيانات والعلاقات", order: 3)
                ]
            )
        ),
        
        StudyTemplate(
            title: "خوارزميات وهياكل البيانات",
            description: "قالب لتوثيق وتحليل الخوارزميات وهياكل البيانات مع أمثلة عملية",
            category: .programming,
            content: TemplateContent(
                title: "خوارزميات وهياكل البيانات",
                folder: "برمجة",
                tags: ["خوارزميات", "هياكل البيانات", "تحليل"],
                content: """
                ## الخوارزمية
                
                **الاسم:** [اسم الخوارزمية]
                **النوع:** [فرز، بحث، ترتيب، إلخ]
                **التعقيد الزمني:** [Big O]
                **التعقيد المكاني:** [Big O]
                
                ## الوصف
                [وصف مفصل لكيفية عمل الخوارزمية]
                
                ## الخطوات
                1. [الخطوة الأولى]
                2. [الخطوة الثانية]
                3. [الخطوة الثالثة]
                
                ## الكود
                ```python
                # أدخل الكود هنا
                def algorithm_name():
                    pass
                ```
                
                ## التحليل
                - **مميزات:** [المميزات]
                - **عيوب:** [العيوب]
                - **حالات الاستخدام:** [الحالات المناسبة]
                """,
                flashcards: [
                    FlashcardTemplate(front: "ما هو تعقيد الخوارزمية الزمني؟", back: "التعقيد الزمني هو [أدخل الإجابة]"),
                    FlashcardTemplate(front: "متى تستخدم هذه الخوارزمية؟", back: "تستخدم هذه الخوارزمية عندما [أدخل الإجابة]"),
                    FlashcardTemplate(front: "ما هي البدائل لهذه الخوارزمية؟", back: "البدائل تشمل [أدخل الإجابة]")
                ]
            )
        ),
        
        // Mathematics Templates
        StudyTemplate(
            title: "حل المعادلات الرياضية",
            description: "قالب منظم لحل وتوثيق المعادلات الرياضية مع شرح الخطوات",
            category: .mathematics,
            content: TemplateContent(
                title: "حل المعادلة",
                folder: "رياضيات",
                tags: ["معادلات", "رياضيات", "حل"],
                content: """
                ## المعادلة الأصلية
                
                $$[أدخل المعادلة هنا]$$
                
                ## الهدف
                إيجاد قيمة [المتغير المطلوب]
                
                ## الخطوات
                
                ### الخطوة 1: [عنوان الخطوة]
                $$[المعادلة بعد الخطوة الأولى]$$
                **الشرح:** [اشرح ما تم في هذه الخطوة]
                
                ### الخطوة 2: [عنوان الخطوة]
                $$[المعادلة بعد الخطوة الثانية]$$
                **الشرح:** [اشرح ما تم في هذه الخطوة]
                
                ## الحل النهائي
                
                $$[الحل النهائي]$$
                
                ## التحقق
                $$[أدخل التحقق بالحل في المعادلة الأصلية]$$
                
                ## ملاحظات إضافية
                - [ملاحظة 1]
                - [ملاحظة 2]
                """,
                flashcards: [
                    FlashcardTemplate(front: "ما هي المعادلة الأصلية؟", back: "المعادلة الأصلية هي [أدخل الإجابة]"),
                    FlashcardTemplate(front: "ما هو الحل النهائي؟", back: "الحل النهائي هو [أدخل الإجابة]"),
                    FlashcardTemplate(front: "كيف نتحقق من صحة الحل؟", back: "نتحقق من الحل عن طريق [أدخل الإجابة]")
                ]
            )
        ),
        
        StudyTemplate(
            title: "مفاهيم الهندسة",
            description: "قالب لتوثيق المفاهيم الهندسية والنظريات مع أمثلة تطبيقية",
            category: .mathematics,
            content: TemplateContent(
                title: "مفهوم هندسي",
                folder: "رياضيات",
                tags: ["هندسة", "نظريات", "مفاهيم"],
                content: """
                ## المفهوم
                
                **الاسم:** [اسم المفهوم أو النظرية]
                **التصنيف:** [هندسة مستوية، فراغية، إلخ]
                
                ## التعريف
                [التعريف الرسمي للمفهوم]
                
                ## النظرية
                
                **النص:** [نص النظرية]
                $$[الصيغة الرياضية للنظرية]$$
                
                ## الإثبات
                
                1. [خطوة الإثبات الأولى]
                2. [خطوة الإثبات الثانية]
                3. [خطوة الإثبات الثالثة]
                
                ## التطبيقات
                
                ### التطبيق 1
                - **الوصف:** [وصف التطبيق]
                - **المثال:** [مثال رقمي]
                
                ### التطبيق 2
                - **الوصف:** [وصف التطبيق]
                - **المثال:** [مثال رقمي]
                
                ## أمثلة محلولة
                [أضف أمثلة محلولة مع الشرح]
                """,
                flashcards: [
                    FlashcardTemplate(front: "ما هو تعريف [المفهوم]؟", back: "[المفهوم] هو [أدخل الإجابة]"),
                    FlashcardTemplate(front: "ما هي النظرية الأساسية؟", back: "النظرية الأساسية تنص على [أدخل الإجابة]"),
                    FlashcardTemplate(front: "ما هي التطبيقات العملية؟", back: "التطبيقات العملية تشمل [أدخل الإجابة]")
                ]
            )
        ),
        
        // Medicine Templates
        StudyTemplate(
            title: "ملخص طبي شامل",
            description: "قالب متخصص لملخصات المواد الطبية مع تنظيم يسهل المراجعة",
            category: .medicine,
            content: TemplateContent(
                title: "ملخص طبي",
                folder: "طب",
                tags: ["طب", "مراجعة", "ملخص"],
                content: """
                ## الموضوع الرئيسي
                
                **المادة:** [اسم المادة]
                **الموضوع:** [اسم الموضوع]
                **التاريخ:** [التاريخ]
                
                ## المفاهيم الأساسية
                
                ### المفهوم 1
                **التعريف:** [التعريف]
                **الأهمية:** [لماذا هذا المفهوم مهم]
                
                ### المفهوم 2
                **التعريف:** [التعريف]
                **الأهمية:** [لماذا هذا المفهوم مهم]
                
                ## التصنيفات
                
                | الفئة | الخصائص | الأمثلة |
                |-------|---------|---------|
                | [الفئة 1] | [الخصائص] | [الأمثلة] |
                | [الفئة 2] | [الخصائص] | [الأمثلة] |
                
                ## الآليات المرضية
                
                1. [الآلية الأولى]
                2. [الآلية الثانية]
                3. [الآلية الثالثة]
                
                ## الأعراض والعلامات
                
                ### الأعراض
                - [العرض 1]
                - [العرض 2]
                
                ### العلامات السريرية
                - [العلامة 1]
                - [العلامة 2]
                
                ## التشخيص
                
                ### الفحوصات المخبرية
                - [الفحص 1]: [القيم الطبيعية والغير طبيعية]
                - [الفحص 2]: [القيم الطبيعية والغير طبيعية]
                
                ### الفحوصات التصويرية
                - [الفحص 1]: [الموجودات]
                - [الفحص 2]: [الموجودات]
                
                ## العلاج
                
                ### العلاج الدوائي
                - [الدواء 1]: [الجرعة والطريقة]
                - [الدواء 2]: [الجرعة والطريقة]
                
                ### العلاج الجراحي
                - [الإجراء 1]: [التفاصيل]
                - [الإجراء 2]: [التفاصيل]
                
                ## المضاعفات
                - [المضاعفة 1]
                - [المضاعفة 2]
                
                ## الوقاية
                - [الوقاية 1]
                - [الوقاية 2]
                """,
                flashcards: [
                    FlashcardTemplate(front: "ما هو تعريف [المفهوم]؟", back: "[المفهوم] هو [أدخل الإجابة]"),
                    FlashcardTemplate(front: "ما هي الأعراض الرئيسية؟", back: "الأعراض الرئيسية تشمل [أدخل الإجابة]"),
                    FlashcardTemplate(front: "ما هو العلاج الموصى به؟", back: "العلاج الموصى به يتضمن [أدخل الإجابة]")
                ]
            )
        ),
        
        StudyTemplate(
            title: "حالة سريرية",
            description: "قالب لتوثيق ودراسة الحالات السريرية بطريقة منهجية",
            category: .medicine,
            content: TemplateContent(
                title: "حالة سريرية",
                folder: "طب",
                tags: ["حالة سريرية", "تشخيص", "علاج"],
                content: """
                ## معلومات المريض
                
                - **العمر:** [العمر]
                - **الجنس:** [الجنس]
                - **الحالة الاجتماعية:** [الحالة]
                
                ## الشكوى الرئيسية
                
                [الشكوى الرئيسية]
                
                ## القصة المرضية الحالية
                
                [تفاصيل القصة المرضية الحالية]
                
                ## القصة المرضية الماضية
                
                - [المرض 1]
                - [المرض 2]
                
                ## القصة العائلية
                
                - [المرض العائلي 1]
                - [المرض العائلي 2]
                
                ## الفحص السريري
                
                ### العلامات الحيوية
                - ضغط الدم: [القيمة]
                - النبض: [القيمة]
                - الحرارة: [القيمة]
                - التنفس: [القيمة]
                
                ### الفحص العام
                [نتائج الفحص العام]
                
                ### الفحص الخاص
                [نتائج الفحص الخاص بالجهاز المصاب]
                
                ## الفحوصات
                
                ### نتائج الفحوصات
                - [الفحص 1]: [النتيجة]
                - [الفحص 2]: [النتيجة]
                
                ## التشخيص التفريقي
                
                1. [التشخيص 1]: [الداعم والمعارض]
                2. [التشخيص 2]: [الداعم والمعارض]
                
                ## التشخيص النهائي
                
                [التشخيص النهائي]
                
                ## الخطة العلاجية
                
                1. [العلاج 1]
                2. [العلاج 2]
                
                ## المتابعة
                
                [خطة المتابعة]
                """,
                flashcards: [
                    FlashcardTemplate(front: "ما هي الشكوى الرئيسية؟", back: "الشكوى الرئيسية هي [أدخل الإجابة]"),
                    FlashcardTemplate(front: "ما هو التشخيص التفريقي؟", back: "التشخيصات التفريقية تشمل [أدخل الإجابة]"),
                    FlashcardTemplate(front: "ما هي الخطة العلاجية؟", back: "الخطة العلاجية تتضمن [أدخل الإجابة]")
                ]
            )
        ),
        
        // Science Templates
        StudyTemplate(
            title: "تجربة علمية",
            description: "قالب لتوثيق التجارب العلمية والمعامل بشكل منظم",
            category: .science,
            content: TemplateContent(
                title: "تجربة علمية",
                folder: "علوم",
                tags: ["تجربة", "معمل", "بحث"],
                content: """
                ## عنوان التجربة
                
                [عنوان التجربة]
                
                ## الهدف
                
                [الهدف من التجربة]
                
                ## الفرضية
                
                [الفرضية التي سيتم اختبارها]
                
                ## المواد والأدوات
                
                - [المادة 1]
                - [المادة 2]
                - [الأداة 1]
                - [الأداة 2]
                
                ## الطريقة
                
                ### الخطوات
                1. [الخطوة 1]
                2. [الخطوة 2]
                3. [الخطوة 3]
                
                ### المتغيرات
                
                - **المتغير المستقل:** [المتغير الذي يتم تغييره]
                - **المتغير التابع:** [المتغير الذي يتم قياسه]
                - **المتغيرات الثابتة:** [المتغيرات التي تظل ثابتة]
                
                ## النتائج
                
                ### البيانات
                | المحاولة | المتغير المستقل | المتغير التابع | الملاحظات |
                |----------|------------------|----------------|-----------|
                | 1 | [القيمة] | [القيمة] | [الملاحظة] |
                | 2 | [القيمة] | [القيمة] | [الملاحظة] |
                | 3 | [القيمة] | [القيمة] | [الملاحظة] |
                
                ### الرسوم البيانية
                [وصف الرسوم البيانية إذا وجدت]
                
                ## التحليل والمناقشة
                
                ### تفسير النتائج
                [تفسير النتائج المحصلة]
                
                ### مقارنة بالفرضية
                [هل النتائج تدعم الفرضية؟ لماذا؟]
                
                ### مصادر الخطأ
                - [مصدر الخطأ 1]
                - [مصدر الخطأ 2]
                
                ## الاستنتاج
                
                [الاستنتاج النهائي من التجربة]
                
                ## التوصيات
                
                - [التوصية 1]
                - [التوصية 2]
                
                ## المراجع
                
                - [المرجع 1]
                - [المرجع 2]
                """,
                flashcards: [
                    FlashcardTemplate(front: "ما هو هدف التجربة؟", back: "هدف التجربة هو [أدخل الإجابة]"),
                    FlashcardTemplate(front: "ما هي الفرضية؟", back: "الفرضية هي [أدخل الإجابة]"),
                    FlashcardTemplate(front: "ما هي النتائج الرئيسية؟", back: "النتائج الرئيسية تشمل [أدخل الإجابة]")
                ]
            )
        ),
        
        StudyTemplate(
            title: "مفهوم علمي",
            description: "قالب لتوثيق المفاهيم العلمية والنظريات مع أمثلة عملية",
            category: .science,
            content: TemplateContent(
                title: "مفهوم علمي",
                folder: "علوم",
                tags: ["مفهوم", "نظرية", "علم"],
                content: """
                ## المفهوم
                
                **الاسم:** [اسم المفهوم]
                **الفرع العلمي:** [الفيزياء، الكيمياء، الأحياء، إلخ]
                
                ## التعريف
                
                [التعريف العلمي للمفهوم]
                
                ## الخلفية التاريخية
                
                - **العالم:** [اسم العالم أو العلماء]
                - **التاريخ:** [تاريخ الاكتشاف أو النظرية]
                - **السياق:** [السياق التاريخي للاكتشاف]
                
                ## المبدأ أو النظرية
                
                **النص:** [نص المبدأ أو النظرية]
                $$[الصيغة الرياضية إذا وجدت]$$
                
                ## الآلية
                
                [شرح كيفية عمل المفهوم]
                
                ## التطبيقات العملية
                
                ### التطبيق 1
                - **الوصف:** [وصف التطبيق]
                - **الأهمية:** [لماذا هذا التطبيق مهم]
                
                ### التطبيق 2
                - **الوصف:** [وصف التطبيق]
                - **الأهمية:** [لماذا هذا التطبيق مهم]
                
                ## الأمثلة التوضيحية
                
                ### المثال 1
                [وصف المثال الأول مع الحل]
                
                ### المثال 2
                [وصف المثال الثاني مع الحل]
                
                ## العلاقات مع المفاهيم الأخرى
                
                - [المفهوم المرتبط 1]: [طبيعة العلاقة]
                - [المفهوم المرتبط 2]: [طبيعة العلاقة]
                
                ## الحدود والقيود
                
                - [الحد 1]
                - [الحد 2]
                
                ## التطورات الحديثة
                
                [أحدث التطورات في هذا المجال]
                """,
                flashcards: [
                    FlashcardTemplate(front: "ما هو تعريف [المفهوم]؟", back: "[المفهوم] هو [أدخل الإجابة]"),
                    FlashcardTemplate(front: "من اكتشف هذا المفهوم؟", back: "اكتشف هذا المفهوم [أدخل الإجابة]"),
                    FlashcardTemplate(front: "ما هي التطبيقات العملية؟", back: "التطبيقات العملية تشمل [أدخل الإجابة]")
                ]
            )
        ),
        
        // Business Templates
        StudyTemplate(
            title: "خطة عمل مشروع",
            description: "قالب احترافي لإنشاء خطط العمل للمشاريع التجارية",
            category: .business,
            isPremium: true,
            price: 4.99,
            content: TemplateContent(
                title: "خطة عمل مشروع",
                folder: "أعمال",
                tags: ["خطة عمل", "مشروع", "أعمال"],
                content: """
                ## ملخص تنفيذي
                
                **اسم المشروع:** [اسم المشروع]
                **الشعار:** [شعار المشروع]
                **الوصف:** [وصف مختصر للمشروع]
                
                ## وصف الشركة
                
                ### الرؤية
                [رؤية الشركة]
                
                ### الرسالة
                [رسالة الشركة]
                
                ### القيم
                - [القيمة 1]
                - [القيمة 2]
                
                ## تحليل السوق
                
                ### حجم السوق
                - [إحصائيات حجم السوق]
                - [نمو السوق المتوقع]
                
                ### الجمهور المستهدف
                - **الخصائص الديموغرافية:** [العمر، الجنس، الدخل، إلخ]
                - **الاهتمامات:** [الاهتمامات والاحتياجات]
                - **السلوك:** [عادات الشراء والاستخدام]
                
                ### المنافسة
                - **المنافسون الرئيسيون:** [قائمة المنافسين]
                - **الميزة التنافسية:** [ما يميز مشروعك]
                
                ## المنتج/الخدمة
                
                ### الوصف
                [وصف المنتج أو الخدمة]
                
                ### المميزات
                - [الميزة 1]
                - [الميزة 2]
                
                ### الفوائد للعملاء
                - [الفائدة 1]
                - [الفائدة 2]
                
                ## نموذج العمل
                
                ### مصادر الدخل
                - [مصدر الدخل 1]
                - [مصدر الدخل 2]
                
                ### هيكل التسعير
                - [استراتيجية التسعير]
                
                ## خطة التسويق
                
                ### استراتيجية التسويق
                - [القنوات التسويقية]
                - [الرسالة التسويقية]
                
                ### الميزانية التسويقية
                - [توزيع الميزانية]
                
                ## الخطة التشغيلية
                
                ### الموقع والتجهيزات
                - [متطلبات الموقع]
                - [المعدات والتجهيزات]
                
                ### الموارد البشرية
                - [الهيكل التنظيمي]
                - [الاحتياجات من الموظفين]
                
                ## الخطة المالية
                
                ### التكاليف التأسيسية
                - [التكلفة 1]: [المبلغ]
                - [التكلفة 2]: [المبلغ]
                
                ### التوقعات المالية
                | السنة | الإيرادات | المصاريف | الربح |
                |-------|-----------|-----------|-------|
                | السنة 1 | [القيمة] | [القيمة] | [القيمة] |
                | السنة 2 | [القيمة] | [القيمة] | [القيمة] |
                | السنة 3 | [القيمة] | [القيمة] | [القيمة] |
                
                ## الجدول الزمني
                
                | المرحلة | البداية | النهاية | المسؤول |
                |---------|---------|---------|---------|
                | [المرحلة 1] | [التاريخ] | [التاريخ] | [الاسم] |
                | [المرحلة 2] | [التاريخ] | [التاريخ] | [الاسم] |
                
                ## المخاطر والتحديات
                
                ### المخاطر المحتملة
                - [المخاطرة 1]: [خطة التخفيف]
                - [المخاطرة 2]: [خطة التخفيف]
                
                ## الخاتمة
                
                [ملخص نهائي وآفاق المستقبل]
                """,
                flashcards: [
                    FlashcardTemplate(front: "ما هي رؤية المشروع؟", back: "رؤية المشروع هي [أدخل الإجابة]"),
                    FlashcardTemplate(front: "من هو الجمهور المستهدف؟", back: "الجمهور المستهدف يتضمن [أدخل الإجابة]"),
                    FlashcardTemplate(front: "ما هي مصادر الدخل؟", back: "مصادر الدخل تشمل [أدخل الإجابة]")
                ]
            )
        ),
        
        // Language Templates
        StudyTemplate(
            title: "تعلم مفردات لغة جديدة",
            description: "قالب فعال لتعلم وتتبع المفردات في اللغات الجديدة",
            category: .language,
            content: TemplateContent(
                title: "مفردات لغة جديدة",
                folder: "لغات",
                tags: ["لغة", "مفردات", "تعلم"],
                content: """
                ## اللغة المستهدفة
                
                **اللغة:** [اسم اللغة]
                **المستوى:** [المستوى الحالي]
                **الهدف:** [الهدف المطلوب]
                
                ## المفردات الجديدة
                
                | الكلمة | النطق | المعنى | مثال | التصنيف |
                |---------|--------|--------|------|----------|
                | [الكلمة 1] | [النطق] | [المعنى] | [مثال] | [اسم، فعل، إلخ] |
                | [الكلمة 2] | [النطق] | [المعنى] | [مثال] | [اسم، فعل، إلخ] |
                
                ## القواعد النحوية
                
                ### القاعدة 1
                **القاعدة:** [وصف القاعدة]
                **الأمثلة:**
                - [المثال الصحيح]
                - [المثال الخاطئ]
                
                ### القاعدة 2
                **القاعدة:** [وصف القاعدة]
                **الأمثلة:**
                - [المثال الصحيح]
                - [المثال الخاطئ]
                
                ## العبارات الشائعة
                
                ### الترحيب والتحية
                - [العبارة 1]: [المعنى]
                - [العبارة 2]: [المعنى]
                
                ### السؤال والطلب
                - [العبارة 1]: [المعنى]
                - [العبارة 2]: [المعنى]
                
                ### الشكر والاعتذار
                - [العبارة 1]: [المعنى]
                - [العبارة 2]: [المعنى]
                
                ## النصوص والمحادثات
                
                ### النص 1
                [النص الأصلي]
                
                **الترجمة:**
                [الترجمة]
                
                **المفردات الجديدة:**
                - [الكلمة]: [المعنى]
                
                ### المحادثة 1
                **المتحدث أ:** [الحوار]
                **المتحدث ب:** [الحوار]
                
                ## التمارين
                
                ### التمرين 1: ترجم
                [الجملة للترجمة]
                
                ### التمرين 2: أكمل
                [الجملة الناقصة]
                
                ## ملاحظات ثقافية
                
                - [ملاحظة ثقافية 1]
                - [ملاحظة ثقافية 2]
                
                ## الموارد الإضافية
                
                - [رابط مورد 1]
                - [رابط مورد 2]
                """,
                flashcards: [
                    FlashcardTemplate(front: "ما معنى [الكلمة]؟", back: "[الكلمة] تعني [أدخل الإجابة]"),
                    FlashcardTemplate(front: "كيف تنطق [الكلمة]؟", back: "تنطق [الكلمة] كـ [أدخل الإجابة]"),
                    FlashcardTemplate(front: "ما هي قاعدة [القاعدة]؟", back: "قاعدة [القاعدة] هي [أدخل الإجابة]")
                ]
            )
        ),
        
        // General Templates
        StudyTemplate(
            title: "ملخص محاضرة",
            description: "قالب عام ومرن لملخصات المحاضرات والدروس",
            category: .general,
            content: TemplateContent(
                title: "ملخص محاضرة",
                folder: "دراسة",
                tags: ["محاضرة", "ملخص", "دراسة"],
                content: """
                ## معلومات المحاضرة
                
                - **المادة:** [اسم المادة]
                - **الموضوع:** [عنوان المحاضرة]
                - **المحاضر:** [اسم المحاضر]
                - **التاريخ:** [التاريخ]
                - **المدة:** [مدة المحاضرة]
                
                ## الأهداف التعليمية
                
                - [الهدف 1]
                - [الهدف 2]
                - [الهدف 3]
                
                ## النقاط الرئيسية
                
                ### النقطة 1
                [شرح النقطة الأولى]
                
                ### النقطة 2
                [شرح النقطة الثانية]
                
                ### النقطة 3
                [شرح النقطة الثالثة]
                
                ## المفاهيم الجديدة
                
                ### المفهوم 1
                **التعريف:** [التعريف]
                **الأهمية:** [لماذا هذا المفهوم مهم]
                
                ### المفهوم 2
                **التعريف:** [التعريف]
                **الأهمية:** [لماذا هذا المفهوم مهم]
                
                ## الأمثلة التوضيحية
                
                ### المثال 1
                [وصف المثال الأول]
                
                ### المثال 2
                [وصف المثال الثاني]
                
                ## النقاط المهمة للتذكر
                
                - [النقطة 1]
                - [النقطة 2]
                - [النقطة 3]
                
                ## الأسئلة المحتملة للامتحان
                
                1. [السؤال 1]
                2. [السؤال 2]
                3. [السؤال 3]
                
                ## الواجبات والمتطلبات
                
                - [الواجب 1]
                - [الواجب 2]
                
                ## الموارد الإضافية
                
                - [رابط 1]
                - [رابط 2]
                
                ## ملاحظات شخصية
                
                [أضف ملاحظاتك الشخصية هنا]
                """,
                flashcards: [
                    FlashcardTemplate(front: "ما هي النقاط الرئيسية؟", back: "النقاط الرئيسية تشمل [أدخل الإجابة]"),
                    FlashcardTemplate(front: "ما هو المفهوم الجديد الأهم؟", back: "المفهوم الجديد الأهم هو [أدخل الإجابة]"),
                    FlashcardTemplate(front: "ماذا يجب أن تتذكر؟", back: "يجب أن تتذكر [أدخل الإجابة]")
                ]
            )
        ),
        
        StudyTemplate(
            title: "خطة مراجعة للامتحان",
            description: "قالب لتنظيم خطة مراجعة شاملة للامتحانات",
            category: .general,
            content: TemplateContent(
                title: "خطة مراجعة للامتحان",
                folder: "دراسة",
                tags: ["امتحان", "مراجعة", "خطة"],
                content: """
                ## معلومات الامتحان
                
                - **المادة:** [اسم المادة]
                - **تاريخ الامتحان:** [التاريخ]
                - **المدة:** [مدة الامتحان]
                - **الشكل:** [اختيار من متعدد، مقالي، عملي، إلخ]
                
                ## المواضيع المطلوبة
                
                - [الموضوع 1]: [الأهمية: عالية/متوسطة/منخفضة]
                - [الموضوع 2]: [الأهمية: عالية/متوسطة/منخفضة]
                - [الموضوع 3]: [الأهمية: عالية/متوسطة/منخفضة]
                
                ## الجدول الزمني للمراجعة
                
                | الأسبوع | المواضيع | الوقت المخصص | الحالة |
                |---------|----------|---------------|---------|
                | الأسبوع 1 | [المواضيع] | [الساعات] | ⏳ |
                | الأسبوع 2 | [المواضيع] | [الساعات] | ⏳ |
                | الأسبوع 3 | [المواضيع] | [الساعات] | ⏳ |
                
                ## استراتيجية المراجعة
                
                ### المراجعة النشطة
                - [استراتيجية 1]
                - [استراتيجية 2]
                
                ### استخدام البطاقات
                - [خطة استخدام البطاقات]
                
                ### حل الامتحانات السابقة
                - [خطة حل الامتحانات]
                
                ## نقاط القوة والضعف
                
                ### نقاط القوة
                - [القوة 1]
                - [القوة 2]
                
                ### نقاط الضعف
                - [الضعف 1]: [خطة التحسين]
                - [الضعف 2]: [خطة التحسين]
                
                ## الموارد الدراسية
                
                - [الكتاب المقرر]
                - [الملاحظات]
                - [الموارد الإلكترونية]
                - [فيديوهات تعليمية]
                
                ## الأيام الأخيرة
                
                ### اليوم قبل الامتحان
                - [نشاط 1]
                - [نشاط 2]
                
                ### يوم الامتحان
                - [التحضير]
                - [النصائح]
                
                ## متابعة التقدم
                
                | التاريخ | المواضيع المنجزة | التقييم |
                |---------|------------------|---------|
                | [التاريخ] | [المواضيع] | [التقييم] |
                
                ## التحفيز والتشجيع
                
                [أضف اقتباسات تحفيزية أو أهداف شخصية]
                """,
                flashcards: [
                    FlashcardTemplate(front: "ما هي المواضيع الأهم؟", back: "المواضيع الأهم تشمل [أدخل الإجابة]"),
                    FlashcardTemplate(front: "ما هي استراتيجية المراجعة؟", back: "استراتيجية المراجعة تتضمن [أدخل الإجابة]"),
                    FlashcardTemplate(front: "ما هي نقاط الضعف التي يجب تحسينها؟", back: "نقاط الضعف تشمل [أدخل الإجابة]")
                ]
            )
        ),

        // Arts Templates
        StudyTemplate(
            title: "تحليل عمل فني",
            description: "قالب منهجي لتفكيك وتحليل النصوص الأدبية والفنية مع محور نقدي موثّق",
            category: .arts,
            content: TemplateContent(
                title: "تحليل العمل الفني",
                folder: "فنون",
                tags: ["فنون", "تحليل", "نقد"],
                content: """
                ## بيانات العمل

                - **العنوان:** [عنوان العمل]
                - **المؤلف/الفنان:** [الاسم]
                - **النوع الأدبي/الفني:** [رواية، قصيدة، مسرحية، لوحة، فيلم]
                - **سنة النشر/الإنتاج:** [السنة]
                - **السياق التاريخي والثقافي:** [الوصف]

                ## الملخص التنفيذي

                [ملخص لا يتجاوز ١٠٠ كلمة للعنصر الأهم في العمل]

                ## البنية

                | الجزء | العنوان | الأفكار الرئيسية | عدد الصفحات |
                |-------|---------|-----------------|-------------|
                | الأول | [العنوان] | [الأفكار] | [العدد] |
                | الثاني | [العنوان] | [الأفكار] | [العدد] |

                ## الشخصيات

                ### [اسم الشخصية]
                - **الدور:** [البطل، الخصم، المساند]
                - **السمات:** [الوصف]
                - **الدافعية:** [ما تريده الشخصية]
                - **التطور:** [كيف تتغير عبر العمل]

                ## الموضوعات الكبرى

                1. [الموضوع الأول]
                2. [الموضوع الثاني]
                3. [الموضوع الثالث]

                ## الأدوات والتقنيات المستخدمة

                - **اللغة والأسلوب:** [الوصف مع أمثلة مقتبسة]
                - **البنية السردية:** [سرد أول، ثالث، متقطع]
                - **الرموز والصور البلاغية:** [التحليل]

                ## المقتبسات المفتاحية

                > [اقتباس مهم]

                **الدلالة:** [اشرح لماذا هذا المقتبس محوري]

                ## نقد موضوعي

                ### نقاط القوة
                - [القوة الأولى]

                ### نقاط الضعف
                - [الضعف الأول]

                ### المقارنة
                [قارن العمل بأعمال مشابهة]

                ## تأثرات ومراجع

                - [اسم العمل] — [العلاقة]
                - [اسم المؤلف/الفنان] — [العلاقة]

                ## خلاصة

                [الحكم النهائي في ثلاثة أسطر]
                """,
                flashcards: [
                    FlashcardTemplate(front: "ما الموضوع الأكبر في «[عنوان العمل]»؟", back: "الموضوع الأكبر هو [أدخل الإجابة]"),
                    FlashcardTemplate(front: "كيف تتطور البنية السردية؟", back: "البنية السردية [أدخل الإجابة]"),
                    FlashcardTemplate(front: "ما أبرز نقطة ضعف في العمل؟", back: "أبرز نقطة ضعف هي [أدخل الإجابة]")
                ]
            ),
            downloadCount: 4_120,
            rating: 4.7,
            author: "MyNotes",
            tags: ["فنون", "تحليل", "نقد", "أدب"]
        ),

        StudyTemplate(
            title: "دفتر ملاحظات الإلهام الفني",
            description: "قالب حر لجمع الأفكار والرسوم الأولية والاختيارات اللونية قبل بدء العمل",
            category: .arts,
            isPremium: true,
            price: 3.99,
            content: TemplateContent(
                title: "دفتر الإلهام",
                folder: "فنون",
                tags: ["فنون", "إلهام", "تصميم"],
                content: """
                ## الفكرة المحورية

                **في جملة واحدة:** [ما الذي أريد أن يقوله العمل؟]
                **لمن؟** [الجمهور المستهدف]
                **لماذا الآن؟** [الدافع]

                ## لوحة المزاج

                | اللون | الكود | الاستخدام |
                |-------|-------|----------|
                | [اللون 1] | #______ | [أين يُستخدم] |
                | [اللون 2] | #______ | [أين يُستخدم] |
                | [اللون 3] | #______ | [أين يُستخدم] |

                **الجملة اللونية:** [العلاقة بين الألوان ومزاج العمل]

                ## المراجع البصرية

                [أدرج المراجع، الرسوم الأولية، أو روابط الأعمال التي تهمك]

                - [مرجع 1] — [لماذا يهمك]
                - [مرجع 2] — [لماذا يهمك]

                ## المفاهيم المتكررة

                - [فكرة 1] — [كيف ستظهر بصريًا]
                - [فكرة 2] — [كيف ستظهر بصريًا]
                - [فكرة 3] — [كيف ستظهر بصريًا]

                ## التكرار والتجريب

                - **فكرة 1:** [النسخة أ / ب / ج وماذا تعلّمك]
                - **فكرة 2:** [النسخة أ / ب / ج]

                ## القيود الإبداعية

                - الوقت المتاح: [المدة]
                - الأدوات المتاحة: [الأدوات]
                - القيود التقنية: [القيود]
                - القيود الإبداعية: [ما لا تريد فعله]

                ## خطة التنفيذ

                1. [الخطوة الأولى] — [المدة]
                2. [الخطوة الثانية] — [المدة]
                3. [الخطوة الثالثة] — [المدة]

                ## سجل التطوّر

                | التاريخ | ما الذي جرّبته | النتيجة | القرار |
                |---------|----------------|---------|--------|
                | [التاريخ] | [التجربة] | [النتيجة] | [القرار] |
                """,
                flashcards: [
                    FlashcardTemplate(front: "ما الفكرة المحورية للعمل؟", back: "الفكرة المحورية هي [أدخل الإجابة]"),
                    FlashcardTemplate(front: "ما لوحة الألوان المختارة؟", back: "لوحة الألوان هي [أدخل الإجابة]"),
                    FlashcardTemplate(front: "ما أول خطوة في التنفيذ؟", back: "أول خطوة هي [أدخل الإجابة]")
                ],
                sections: [
                    TemplateSection(title: "قائمة المراجع", content: "كل شيء يلهمك بصريًا", order: 1),
                    TemplateSection(title: "الملاحظات الحرة", content: "أي فكرة لم تجد لها مكانًا بعد", order: 2)
                ],
                customFields: [
                    "الموعد النهائي": "[التاريخ]",
                    "عدد المراجعات": "[العدد]"
                ]
            ),
            downloadCount: 2_860,
            rating: 4.5,
            author: "MyNotes",
            tags: ["فنون", "إلهام", "لوحة", "تصميم"]
        )
    ]
}