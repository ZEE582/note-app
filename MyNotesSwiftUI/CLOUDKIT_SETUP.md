# CloudKit setup

The SwiftUI target uses SwiftData with `cloudKitDatabase: .automatic`.
This keeps notes local-first and lets CloudKit synchronize records when the
user is signed in to iCloud. No application login is required.

## Xcode setup on macOS

1. Create or open the iOS/iPadOS/macOS SwiftUI app target.
2. Add `MyNotes.entitlements` to the target and replace
   `iCloud.com.mynotes.app` with the container identifier owned by the
   Apple Developer team.
3. In **Signing & Capabilities**, add **iCloud** and enable **CloudKit**.
4. Create the same container in CloudKit Dashboard and deploy the development
   schema before testing on multiple devices.
5. Use the same Apple Developer team and bundle identifier for iPhone, iPad,
   and Mac targets.

If CloudKit cannot be initialized, `NotesStore` falls back to a persistent
local SwiftData store and surfaces the state as `تخزين محلي`. Once the
container and entitlements are configured correctly, the app reports
`مزامنة iCloud مفعلة`.

## مشاركة القراءة فقط والتعاون

من محرر الملاحظة، افتح قائمة الأدوات واختر **إنشاء رابط قراءة فقط**. ينشئ
`CloudKitCollaboration` سجل `SharedNoteSnapshot` و`CKShare` بصلاحية
`readOnly`، ثم يعرض رابط CloudKit عبر `ShareLink`. هذا ليس رابط HTTP مستضافًا
من التطبيق ولا يحتاج backend خاصًا. المصدر الأصلي يظل في SwiftData محليًا؛
وعند حفظ ملاحظة سبق مشاركتها، يحاول التطبيق تحديث snapshot في CloudKit دون
حجب الحفظ المحلي.

هذه الطبقة مقصودة كحد CloudKit واضح لأن مشاركة SwiftData المباشرة (`CKShare`
على `ModelContainer`) تختلف واجهاتها حسب إصدار Xcode/SDK وتحتاج مخططًا
سحابيًا واختبار قبول الدعوات. المشاركة الحالية عملية كرابط قراءة فقط، وليست
تحريرًا متزامنًا حرفًا بحرف بين عدة محررين. لا تُعرض حالة CloudKit للمستخدم
على أنها backend أو استضافة ويب.

## التصدير

من قائمة الأدوات في `NoteEditorView` يمكن تصدير الملاحظة إلى Markdown أو PDF
باستخدام `FileDocument` وواجهة النظام. التصدير لا يسطّح ملف PDF المستورد ولا
يعدل المصدر؛ bookmark الملف يبقى منفصلًا، ويمكن إضافة طبقة PDFKit لاحقًا عند
الحاجة إلى تصدير annotations على نسخة.

## Spotlight indexing

The native target indexes note titles, typed content, folders, tags, and
iPad handwriting recognized through Vision. Spotlight results use the note
UUID and open the matching note in the app. This requires testing the native
target on iOS or macOS; the Expo web fallback cannot register items in device
Spotlight.
