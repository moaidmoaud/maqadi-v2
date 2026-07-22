# سجل التغييرات

## Phase 8.2.1 — Product Matching v2 Candidate Generation

### Candidate discovery
- Added a dedicated English/Arabic-safe normalization stage for case, punctuation, and repeated whitespace cleanup.
- Added read-only Receipt Line text and catalog ports plus candidate generation that discovers every exact or shared-token catalog candidate, preserves catalog order, prevents duplicate product IDs, and assigns no score, ranking, confidence decision, or winner.
- Added strongly typed discovery evidence and extended the serializable Product Match trace with the normalized query, generated IDs/count/order, catalog evaluation order, and per-candidate discovery evidence.

## Phase 8.2 — Product Matching v2 Foundation

### Receipt-line matching contract
- Added an isolated Product Matching v2 domain with immutable candidates, per-line results, typed statuses and reasons, and JSON-safe decision traces prepared for future matching diagnostics.
- Added a `ReceiptLine`-based service interface and an explicit pending placeholder implementation without introducing matching rules or changing the current OCR-based Product Matching v1 flow.
- Kept the foundation independent from OCR, Receipt Understanding, repositories, inventory, purchases, shopping, Flutter, persistence, and external packages.

## RC-1.3 — Receipt Line Decision Trace Audit

### Internal decision diagnostics
- Added immutable per-anchor candidate evaluation traces with typed final reasons, stable evaluation order, accepted/rejected outcomes, element roles, row/column placement, and every spatial metric used by attachment selection.
- Added JSON-safe serialization for decision traces and a read-only Decision Trace section in the existing Receipt Line Builder debug screen.
- Preserved all Receipt Line grouping order, thresholds, calibration values, outputs, benchmark behavior, Receipt Understanding, and Product Matching flows.

## RC-1.2 — Receipt Line Runtime Debug Integration

### Internal runtime diagnostics
- Added a read-only `عرض أسطر الإيصال` action from the successful Receipt Understanding debug screen to the existing Receipt Line Builder debug screen, reusing the already-produced Understanding result.
- Added immutable engine trace data for calibration policy values, median height, canonical order, element row/column placement, row and column comparisons, exact split decisions, line completeness, anchors, role assignments, rejected candidates, and unassigned reasons.
- Added a Spatial Trace view that displays engine-produced diagnostics without recalculating geometry or changing calibration, grouping, OCR, or Product Matching behavior.

### Architecture and quality
- Kept the trace derived, deterministic, read-only, in-memory, and independent from Flutter, repositories, persistence, matching, inventory, purchases, and shopping.
- Added focused navigation, single-invocation, trace generation, split-decision, missing-geometry, determinism, presentation, architecture-boundary, and unchanged-grouping tests.

## Sprint RC-1 — Receipt Calibration & Benchmark Framework

### Calibration and measurement
- Added an immutable `ReceiptCalibrationPolicy` that centralizes the existing median-height-normalized row and column grouping tolerances without changing their defaults or the Receipt Intelligence architecture.
- Added a deterministic, read-only benchmark runner with manually declared ground truth, stable fixture keys, Understanding and Receipt Line comparisons, transparent metrics, mismatch details, and a de-duplicated manual-correction estimate.
- Added the first official `DAN-0001` benchmark identifier as a committed synthetic/redacted OCR proxy; the private source image remains local and its accuracy is not claimed by the automated benchmark.

### Debugging and quality
- Added expected, actual, and mismatch overlays plus richer engine-provided Receipt Line evidence display for internal calibration and regression review.
- Documented ADR-040 through ADR-045, metric formulas, fixture privacy, calibration acceptance, and the workflow for adding future receipts.
- Added focused policy, comparison, runner, widget, architecture-boundary, deterministic, and large-fixture tests without adding packages or production persistence.

## Phase 8.1 — Receipt Line Builder

### Receipt line structure
- Added a deterministic, read-only Receipt Line Builder that groups `ReceiptElement` references into `Complete`, `Partial`, and `Orphan` structural lines without duplicating element data.
- Added median-height-normalized row-first and column-second grouping, spatial-priority role attachment, receipt-total protection, deterministic line IDs, rejected-candidate evidence, and reference-only unassigned results.
- Added a read-only debug screen for source elements, grouped lines, completeness filtering, grouping overlays, element highlighting, unassigned elements, and engine-generated evidence.

### Architecture and quality
- Kept line construction independent from OCR providers, repositories, product matching, purchases, inventory, shopping, persistence, and business validation.
- Documented RFC-006 and ADR-033 through ADR-039 in `docs/architecture/receipt-line-builder.md`.
- Added 48 engine, service, presentation, architecture, normalization, determinism, failure-mapping, and large-receipt tests.

## Phase 8.0 — Receipt Understanding Engine

### Receipt structure
- Added a provider-independent, deterministic Receipt Understanding Engine that classifies each OCR block into exactly one of eleven structural element types without splitting or merging blocks.
- Added canonical spatial ordering, top/body/footer zones, Arabic and English structural normalization, retailer-agnostic structural dictionaries, and fixed classification precedence.
- Added immutable classification evidence with nullable OCR confidence and geometry, deterministic unsigned FNV-1a element identifiers, and safe handling of missing OCR metadata.
- Added a read-only debug screen for original OCR blocks, classified elements, type filtering, confidence and evidence inspection, and bounding-box overlays.

### Architecture and quality
- Kept receipt understanding isolated from products, matching, purchases, inventory, shopping, repositories, and business dictionaries; OCR results enter only through `ReceiptUnderstandingService`.
- Documented RFC-005 and ADR-030/ADR-031 in `docs/architecture/receipt-understanding-engine.md`.
- Added 48 engine, service, presentation, architecture, ordering, determinism, failure-mapping, mixed-language, and large-receipt tests.

## Phase 7.3 — Shopping Recommendation Engine

### Shopping recommendations
- Added a deterministic, read-only Shopping Recommendation Engine with exactly four business decisions: `Ignore`, `Watch`, `BuySoon`, and `BuyNow`.
- Added the approved RFC-004 mapping from authoritative Low Stock predictions and Health states, with six explicit reason codes and product-specific failures for unsupported or malformed combinations.
- Added structured explanations containing the recommendation, reason, Health state, Consumption evidence, Low Stock prediction, immutable evidence, and summary.
- Added a read-only Shopping Recommendations screen with loading, results, empty and error states, retry, refresh, four-state filtering, explanations, product failures, and direct product navigation.

### Architecture and quality
- Added backward-compatible Low Stock orchestration so Health and Consumption are each evaluated once and their existing Results are reused for one Low Stock evaluation and O(products) recommendation joining.
- Kept Consumption evidence explanatory only; recommendation code performs no consumption-rate, projection, threshold, horizon, confidence, quantity, persistence, notification, or shopping-list calculations or mutations.
- Documented RFC-004, ADR-028, and ADR-029 in `docs/architecture/shopping-recommendation-engine.md`.
- Added 40 engine, service, presentation, architecture, deterministic, failure-mapping, large-batch, backward-compatibility, and no-write tests.

## Phase 7.2 — Low Stock Detection Engine

### Low-stock prediction
- Added a read-only, deterministic Low Stock Detection Engine that consumes only `InventoryHealthResult` and `ConsumptionResult` and returns `Normal`, `Monitor`, or `LowSoon`.
- Added fixed fourteen-day projections with seven-day and two-consumption-event evidence minimums, explicit per-product and batch failures, and structured engine-generated explanations.
- Added a read-only Low Stock Outlook screen with loading, results, empty and error states, refresh, prediction filtering, explanations, and direct product navigation.

### Architecture and quality
- Kept all predictions derived and non-persistent with one Health evaluation, one Consumption evaluation, O(products) joining, and no inventory, purchase, shopping, notification, or repository writes.
- Documented RFC-003, ADR-026, and ADR-027 in `docs/architecture/low-stock-engine.md`.
- Added 40 engine, service, presentation, architecture, deterministic, large-batch, failure-mapping, and no-write tests.

## Phase 7.1 — Consumption Engine

### Consumption history
- Added a provider-independent, read-only Consumption Engine that derives how products were consumed from existing inventory movements.
- Added immutable consumption snapshots, events, profiles, results, explanations, and explicit failures without persistence or caching.
- Added typed normalization that distinguishes recorded consumption from purchases, additions, adjustments, and batch removals.
- Added a read-only Consumption screen with product selection, loading, empty and error states, refresh, history summaries, event history, and engine-generated explanations.

### Architecture and quality
- Added a single-capture `InventoryService` reader and one-pass movement grouping without `PurchaseRepository` or `SharedPreferences` access.
- Documented RFC-002 and ADR-021 through ADR-025 in `docs/architecture/consumption-engine.md`.
- Added event-builder, engine, service, presentation, architecture, deterministic, large-history, and no-write tests.

## Phase 7.0 — Inventory Health Engine

### Inventory health
- Added a read-only, deterministic health engine with exactly four states: `Unknown`, `Healthy`, `LowStock`, and `OutOfStock`.
- Added structured explanations containing the status, reason code, quantity, threshold, unit, evaluation timestamp, and summary for every evaluated product.
- Added a single-pass adapter over the already-loaded `InventoryService`, policy resolution, explicit failure mapping, and urgency-first result ordering without persistence or caching.
- Added a read-only Inventory Health screen with loading, results, empty, error, refresh, filtering, explanations, and direct product navigation.

### Architecture and quality
- Documented RFC-001 and ADR-018 through ADR-020 in `docs/architecture/inventory-health.md`.
- Added engine, service, presentation, architecture, deterministic, large-batch, and no-write tests.

## Phase 6.4 — تثبيت منصة الإيصالات

### الاعتمادية وسلامة البيانات
- جعل تأكيد مسودة الإيصال صريح الحالة ومتكررًا بأمان، بحيث تتشارك الطلبات المتزامنة عملية إنشاء واحدة ولا تنشئ إعادة المحاولة بعد النجاح عملية شراء إضافية.
- نقل عقد إنشاء الشراء إلى نطاق الشراء وإزالة اعتماد `PurchaseService` على نماذج استيراد الإيصالات.
- تنفيذ عمليات إنشاء وتعديل وحذف المشتريات كوحدة عمل متسلسلة مع استعادة حتمية للمشتريات والمخزون والدفعات وسجل الأسعار عند فشل أي حد كتابة.

### دورة الحياة والبناء
- إنهاء كامل مكدس مسار معالجة الإيصال بعد نجاح الاستيراد، ومنع الإلغاء أو الرجوع غير الآمن أثناء التأكيد.
- تنظيف ملفات الصور المؤقتة الخاصة بالتطبيق بعد النجاح والفشل والإلغاء وانتهاء المهلة والتخلص من الواجهة، دون حذف ملفات الكاميرا أو المعرض المملوكة للمستخدم.
- إضافة ملفات Android القياسية المطلوبة للبناء من نسخة مستنسخة نظيفة، وإزالة اعتماد مسار CI على إنشاء منصة Android مؤقتة.
- إضافة اختبارات لعدم تكرار التأكيد، والتنقل، وحدود الفشل والاستعادة، وتسلسل الكتابات، وإلغاء موارد OCR ودورة حياة الالتقاط.

## Phase 6.3 — استيراد الإيصالات

### الجديد
- إضافة نطاق `ReceiptDraft` مستقل وقابل للتحرير لبنود الإيصال والبيانات الوصفية والإجماليات والتنبيهات والأسطر غير المطابقة، مع إبقائه منفصلًا تمامًا عن نموذج الشراء النهائي.
- إضافة `ReceiptImportService` لإنشاء المسودة من نتائج OCR ومطابقة المنتجات، وتعديل المنتج والكمية والسعر، وإضافة البنود وإزالتها، والتحقق وإدارة الإلغاء وتحويل حالات الفشل.
- إضافة شاشة مراجعة كاملة تدعم اختيار متجر وتاريخ، واستبدال المنتج والبحث اليدوي، وتعديل الكميات والأسعار، ومراجعة التنبيهات والإجماليات، والإلغاء والتأكيد.
- ربط مسار OCR والمطابقة بالمراجعة دون إنشاء أي عملية شراء قبل تأكيد المستخدم.

### المعمارية والاختبارات
- إضافة نقطة تأكيد مخصصة داخل `PurchaseService` بوصفها المسار الوحيد لتحويل `ReceiptDraft` إلى عملية شراء، مع استمرار تحديث المخزون وسجل الأسعار عبر سير الشراء القائم.
- منع واجهة الاستيراد من الوصول إلى المستودعات أو إنشاء نماذج شراء، وإضافة حالات فشل صريحة واختبارات للمسودة والتحرير والتحقق والإلغاء والتأكيد وحالات الواجهة باستخدام بدائل وهمية.

## Phase 6.2 — مطابقة المنتجات

### الجديد
- إضافة محرك مستقل لمطابقة نص OCR مع كتالوج المنتجات، مع توليد عدة مرشحين وترتيبهم حسب الثقة دون إنشاء مشتريات أو تعديل المخزون.
- إضافة قواعد قابلة للتوسعة لتوحيد النص الإنجليزي والعربي والمسافات وعلامات الترقيم، واستراتيجيات مرتبة للتطابق التام والموحد والأسماء البديلة والتطابق التقريبي.
- إضافة نماذج نطاق مستقلة للطلب والنتيجة والثقة والفشل وشرح المطابقة المنظم، بحيث يوضح كل مرشح النصوص الموحدة والاستراتيجية والتشابه والثقة النهائية.
- إضافة شاشة مطابقة بحالات التحميل والمرشحين وعدم وجود نتائج والخطأ، مع اختيار المرشح والبحث اليدوي وتخطي السطر وإعادة المحاولة عبر `ProductMatchingService` فقط.

### المعمارية والاختبارات
- إبقاء محرك المطابقة مستقلًا عن مزود OCR وGoogle ML Kit، مع مستودع كتالوج للقراءة فقط واستراتيجيات قابلة للاستبدال ودون أي اعتماد على المشتريات أو المخزون أو الأسعار.
- إضافة اختبارات للتوحيد والاستراتيجيات والثقة والترتيب وشرح كل استراتيجية وتحويل حالات الفشل وسلوك الواجهة باستخدام مستودعات وهمية فقط.

## Phase 6.1 — منصة التعرف على النص

### الجديد
- إضافة نطاق OCR مستقل بنماذج طلب ونتيجة منظمة إلى كتل وأسطر وكلمات، مع دعم اختياري للثقة وموقع النص دون تضمين أي بنية خاصة بمزود خارجي.
- إضافة واجهة `ReceiptOcrProvider` قابلة للاستبدال للإمكانات والتوفر والتعرف، وخدمة `ReceiptOcrService` للتحقق من الطلب وتحويل أخطاء المزود إلى حالات فشل صريحة وآمنة.
- إضافة مزود Google ML Kit واحد مع محول معزول بالكامل داخل طبقة البنية التحتية، بحيث لا تصل أنواع SDK إلى الخدمة أو الواجهة أو نماذج النطاق.
- ربط صورة الإيصال المتحقق منها بشاشة قراءة OCR ذات حالات تحميل ونجاح وخطأ وإعادة محاولة، دون تفسير الإيصال أو مطابقة المنتجات أو إنشاء مشتريات.

### اللغات والاختبارات
- تجهيز نماذج الطلب والإمكانات لتفضيلات العربية والإنجليزية؛ يعلن مزود ML Kit الحالي دعم الإنجليزية وفق إمكانات نموذج Latin، ويمكن إضافة مزود يدعم العربية دون تغيير الخدمة أو الواجهة.
- إضافة اختبارات بعيدة عن SDK للتجريد وسلوك الخدمة والنجاح والنتيجة الفارغة والصورة غير المقروءة وعدم توفر المزود واللغة غير المدعومة وتحويل الأخطاء وحالات الواجهة.

## Phase 6.0 — التقاط الإيصالات

### الجديد
- إضافة سير مؤقت ومعزول لالتقاط صورة الإيصال بالكاميرا أو اختيارها من المعرض، مع معاينة واستبدال الصورة وقصها وتدويرها وإعادة ضبطها قبل المتابعة.
- إضافة جلسة إيصال غير مستمرة بحالات صريحة للفراغ والاختيار والتعديل والجاهزية والمعالجة والخطأ والإلغاء، دون حفظ الصورة أو ربطها بنطاقات المشتريات والمخزون والأسعار والمتاجر.
- التحقق من وجود الصورة وصيغتها وقابلية فكها وأبعادها داخل خدمة مستقلة، مع نقطة توسعة لقواعد جودة مستقبلية دون تفعيل فحوص جودة في هذه المرحلة.
- إضافة واجهة مجردة فقط لمزود OCR المستقبلي، دون أي تنفيذ OCR أو مزود خارجي أو تحليل لمحتوى الإيصال.

### الاختبارات والتوافق
- إضافة اختبارات للخدمة وحالات الانتقال والكاميرا والمعرض والفشل والتدوير والقص وإعادة الضبط والإلغاء واستبدال الصورة، إلى جانب اختبارات واجهة وحالات التحقق.
- إبقاء نطاق الالتقاط مستقلًا عن مخططات ومستودعات وبيانات المستخدم الحالية، مع إضافة إعداد Android الضروري لواجهة القص فقط.

## Phase 5.4 — إدارة المتاجر

### الجديد
- إضافة نطاق متاجر كامل بحقول الاسم والفرع والملاحظات والحالة وتواريخ الإنشاء والتحديث، مع مستودع مستقل وخدمة لقواعد العمل.
- إضافة شاشة إدارة متاجر تدعم البحث والتصفية والإضافة والتعديل والأرشفة والاستعادة والحذف الآمن، مع حالات التحميل والفراغ والخطأ.
- ربط إنشاء المشتريات بالمتاجر النشطة فقط، مع استمرار عرض المتاجر المؤرشفة في السجل ودعم تعديل المشتريات التاريخية المرتبطة بها.

### قواعد العمل والتوافق
- منع تكرار أسماء المتاجر النشطة دون حساسية لحالة الأحرف، ومنع حذف متجر له مشتريات مع رسالة واضحة وإتاحة الأرشفة بدلًا من ذلك.
- إضافة مخزن بيانات مستقل بإصدار قابل للتكرار، واستيراد مراجع المتاجر القديمة من المشتريات دون إعادة كتابة بيانات الشراء أو فقدانها.
- إبقاء الواجهات متصلة بالخدمات فقط، والمستودعات مسؤولة عن الاستمرارية دون منطق أعمال.

## Phase 5.3 — أساس سجل الأسعار

### الجديد
- إضافة سجل أسعار تاريخي مستقل وغير قابل للتغيير يربط المنتج وعملية الشراء وبند الشراء والمتجر والتاريخ والسعر النهائي للوحدة والعملة.
- تسجيل الأسعار تلقائيًا عند نجاح الشراء، وتطبيق فروقات البنود فقط عند التعديل، وحذف سجلات العملية وحدها بعد اجتياز قواعد الحذف.
- إضافة `PriceHistoryService` للاستعلام عن سجل المنتج مرتبًا من الأحدث، مع شاشة قراءة فقط وحالات التحميل والفراغ والخطأ.

### المعمارية والتوافق
- حفظ السجل في مستودع ومفتاح إصدار مستقلين بترحيل إضافي قابل للتكرار، دون تعديل مخططات المشتريات أو المخزون الحالية.
- إبقاء جميع قرارات تسجيل الأسعار ومطابقة فروقات الشراء داخل الخدمات، ومنع واجهة سجل الأسعار من الوصول المباشر إلى المستودعات.

## Phase 5.2 — سير عمل المشتريات

### الجديد
- إضافة شاشة سجل مشتريات قابلة للبحث والتصفية حسب المتجر والتاريخ أو نطاق تاريخ، مع ترتيب الأحدث أولًا وحالات التحميل والفراغ والخطأ.
- إضافة شاشة تفاصيل تعرض لقطة العملية المالية وكامل بيانات البنود والدفعات المرتبطة.
- إضافة سير عمل متكامل لإنشاء المشتريات وتعديلها وحذفها الآمن، مع اختيار المنتجات والتواريخ وحساب الإجماليات تلقائيًا.

### قواعد العمل والتوافق
- إبقاء التحقق والحسابات والبحث والتصفية وقرارات الحذف داخل `PurchaseService`، وتواصل واجهات المشتريات مع الخدمة فقط.
- استخدام فروقات الكميات عند التعديل والمحافظة على الدفعات المرتبطة واللقطات المالية والتواريخ التاريخية.
- منع حذف عملية استُهلكت أو عُدّلت إحدى دفعاتها، مع رسالة واضحة، ودون تغيير مخطط البيانات أو مستودعات الإصدار السابق.

## Phase 5.1 — أساس المشتريات

### الجديد
- إضافة نماذج غير قابلة للتغيير للمتجر والمشتريات وبنود المشتريات، مع دعم التحويل الآمن من وإلى JSON.
- إضافة مستودع مستقل للمشتريات يدعم CRUD والسجل والاستعلام حسب التاريخ والمتجر وتفاصيل البنود.
- إضافة خدمة مشتريات مسؤولة عن التحقق وحساب الإجمالي والخصومات والضرائب وتنسيق عمليات الحفظ.
- ربط حفظ المشتريات بدفعات المخزون الحالية عبر `InventoryService` دون تكرار منطق المخزون.

### التوافق والترحيل
- إضافة مخزن بيانات مستقل بإصدار مخطط خاص بالمشتريات وترحيل إضافي قابل للتكرار، دون تعديل مفاتيح أو بيانات المستخدم الحالية.

## إصلاح بناء Android

- تفعيل core library desugaring وإضافة `desugar_jdk_libs` المتوافق لإصلاح بناء APK للإصدار مع الإشعارات المحلية.

## Phase 4.6 — التقارير والتصدير

### الجديد
- إضافة ستة تقارير PDF احترافية للمخزون وقائمة التسوق والصلاحية والمخزون المنخفض وملخص لوحة المعلومات، مع تاريخ الإنشاء وإجماليات المخزون وترقيم الصفحات وبيانات التطبيق.
- إضافة ملف Excel بأوراق مستقلة للمخزون وقائمة التسوق وتفاصيل الدفعات وملخص لوحة المعلومات.
- إضافة تصدير CSV للمخزون وقائمة التسوق، مع مشاركة الملفات عبر واجهة المشاركة في المنصة وطباعة تقارير PDF مباشرةً.
- إضافة شاشة تقارير موحدة مع تصفية حسب التصنيف وحالات المخزون والصلاحية قبل التصدير.

### المعمارية والتوافق
- عزل إنشاء الملفات في `ReportService` وإبقاء قرارات المخزون والصلاحية داخل `InventoryService`، مع فصل المشاركة والطباعة عن إنشاء التقارير.
- عدم تغيير `Repository` أو مخطط JSON أو بيانات المستخدمين المحفوظة.

## Phase 4.5 — الإشعارات الذكية

### الجديد
- إضافة إشعارات محلية للمخزون المنخفض، ونفاد المخزون، والدفعات القريبة من الانتهاء، والمنتهية الصلاحية.
- إضافة إعدادات مستقلة لمدة تذكير الصلاحية (7 أو 14 أو 30 يومًا)، ووقت الإشعار، وتفعيل كل نوع أو تعطيله.
- إضافة بطاقة ملخص للإشعارات الذكية وعدد الإشعارات المعلقة في لوحة المعلومات.

### المعمارية والتوافق
- إبقاء جميع قرارات الإشعارات ومواعيدها داخل `InventoryService`، مع اقتصار طبقة المنصة على جدولة القرارات الجاهزة.
- حفظ الإعدادات في مفتاح اختياري جديد مع قيم افتراضية آمنة عند تحميل بيانات المستخدمين السابقين.
- عدم تغيير مفاتيح بيانات المخزون أو القوائم أو بنية JSON الحالية.

## Phase 4.4 — دعم الباركود وQR

### الجديد
- مسح الباركود ورموز QR بالكاميرا مع فتح المنتج أو الدفعة المرتبطة مباشرةً.
- اقتراح إنشاء منتج جديد عند مسح باركود غير مسجل مع تعبئة الباركود تلقائيًا.
- دعم باركود أساسي وعدة باركودات إضافية لكل منتج مع النسخ والإضافة والمسح.
- إنشاء رمز QR داخلي لكل منتج ورمز اختياري لكل دفعة دون اتصال بالإنترنت.
- توسيع البحث الشامل ليشمل الباركود إلى جانب الاسم والتصنيف ومعرّف الدفعة.

### المعمارية والتوافق
- إبقاء التطبيع والبحث ومنع التكرار وإنشاء وحل روابط QR داخل `InventoryService`.
- إضافة حقول JSON اختيارية فقط مع قراءة الحقل القديم `barcode` عند وجوده، دون تغيير مفاتيح المستودع أو مخطط الحفظ.
- استمرار تحميل المنتجات القديمة دون باركود مع الحفاظ على جميع بياناتها ودفعاتها.

## Phase 4.3 — تحليلات لوحة المعلومات

### الجديد
- إضافة ملخص شامل للمنتجات والدفعات والكميات وحالات المخزون والصلاحية وقائمة التسوق.
- إضافة إجراءات سريعة لإضافة منتج وفتح قائمة التسوق والصلاحية وإدارة الدفعات.
- عرض أعلى المنتجات حسب الكمية، والأقل مخزونًا، والمضافة والمحدثة مؤخرًا.
- إضافة مخططات Flutter خفيفة لتوزيع حالة المخزون والصلاحية وتصنيفات المنتجات دون حزم إضافية.
- إضافة بحث شامل باسم المنتج أو التصنيف أو معرّف الدفعة مع فتح المنتج مباشرةً.

### المعمارية والأداء
- تنفيذ جميع التجميعات والترتيب والبحث داخل `InventoryService` مع تخزين مؤقت يُبطل تلقائيًا عند تغير المخزون أو اليوم أو قائمة التسوق.
- اشتقاق تواريخ الإضافة والتحديث من حركات المخزون وتواريخ الدفعات الحالية دون أي تغيير على مخطط الحفظ.
- استمرار استخدام `Repository` الحالي وملفات JSON القديمة دون ترحيل أو فقدان بيانات.

## Phase 4.2 — ذكاء قائمة التسوق

### الجديد
- إضافة حد أدنى قابل للتعديل لكل منتج في المخزن، بقيمة افتراضية 1 للبيانات القديمة.
- تصنيف المخزون إلى طبيعي، منخفض، أو نافد من خلال `InventoryService`.
- مزامنة قائمة التسوق تلقائيًا عند انخفاض المخزون، وإزالة العنصر عند إعادة تعبئته، ومنع التكرار.
- إضافة بطاقات ملخص للمخزون المنخفض والنافد وعدد عناصر قائمة التسوق إلى اللوحة الرئيسية.
- عرض الكمية الحالية والحد الأدنى وشارة حالة المخزون في شاشة المنتج.
- إضافة البحث والترتيب الأبجدي ومرشحات المخزون المنخفض والنافد إلى شاشة التسوق.

### المعمارية والتوافق
- إبقاء جميع حسابات المخزون وقواعد المزامنة والبحث والفرز داخل `InventoryService`.
- إضافة ربط اختياري فقط بين عنصر التسوق ومنتج المخزن دون تغيير مفاتيح التخزين أو كسر JSON القديم.
- ترحيل المنتجات القديمة التي لا تحتوي على حد أدنى تلقائيًا إلى القيمة 1 دون فقدان البيانات.

## Phase 4.1 — إدارة الصلاحية

### الجديد
- تصنيف دفعات المخزون إلى طازجة، قريبة الانتهاء خلال 30 يومًا، أو منتهية.
- عرض شارة ملونة وعدد الأيام المتبقية لكل دفعة في شاشة إدارة الدفعات.
- إضافة شاشتي قريب الانتهاء ومنتهي الصلاحية مع البحث والترتيب حسب أقرب تاريخ انتهاء.
- فتح منتج المخزن مباشرةً من قوائم الصلاحية.
- إضافة بطاقتي ملخص للدفعات القريبة والمنتهية في اللوحة الرئيسية.

### المعمارية والتوافق
- جميع حسابات الأيام والحالات والفرز والبحث منفذة داخل `InventoryService`.
- لا تغيير على مخطط التخزين أو مفاتيح `Repository`، والدفعات بدون تاريخ انتهاء تظل متوافقة وتُعامل كطازجة.

## Phase 3.2 — واجهة إدارة الدفعات

### الجديد
- إضافة شاشة مستقلة لإدارة دفعات كل منتج في المخزن.
- دعم إضافة الدفعة وتعديلها وحذفها مع الكمية وتاريخ الشراء وتاريخ الانتهاء الاختياري.
- دعم معرّف اختياري وملاحظات لكل دفعة.
- عرض إجمالي كمية المنتج وعدد دفعاته وترتيب الاستهلاك FIFO.

### المعمارية والتوافق
- الإبقاء على `InventoryService` كمسؤول وحيد عن حسابات الدفعات وحركات الكميات.
- استمرار الحفظ من خلال طبقة `Repository` فقط مع الحفاظ على مفاتيح وحقول JSON السابقة.
- الحفاظ على ترحيل الرصيد القديم إلى دفعة افتتاحية بدون تغيير مخطط التخزين.

## Phase 3.1 — طبقة المخزون

### الجديد
- إضافة `InventoryService` لتجميع قواعد المخزون وحركات الكميات خارج الواجهة.
- إضافة طبقة `Repository` مستقلة لحفظ وتحميل بيانات التطبيق محليًا.
- دعم أكثر من دفعة للمنتج الواحد مع تاريخ استلام مستقل لكل دفعة.
- تجهيز الاستهلاك بطريقة FIFO، بحيث تُستهلك الدفعات الأقدم أولًا.
- ربط حركات المخزون بتوزيع الكمية على الدفعات لتسهيل التتبع لاحقًا.

### التوافق والتحسينات
- ترحيل كميات المخزون القديمة تلقائيًا إلى دفعة افتتاحية عند التحميل.
- الإبقاء على مفاتيح التخزين وحقول JSON القديمة لضمان توافق البيانات المحفوظة.
- فصل نماذج البيانات ومنطق المخزون والحفظ عن ملف الواجهة الرئيسي.
- الحفاظ على شاشات وسلوكيات التطبيق الحالية دون تغييرات مرئية.
- إضافة اختبارات للدفعات المتعددة وFIFO وترحيل البيانات القديمة وطبقة الحفظ.

## Sprint 2.6 — المرحلة الثانية (Beta)

### الجديد
- ربط قائمة المقاضي بمخزن المنزل.
- إضافة زر **تم وضع المقاضي في المنزل** لنقل الأغراض المشتراة.
- تحديث كمية المنتج تلقائيًا عند وجوده في المخزن.
- إنشاء المنتج تلقائيًا عند عدم وجوده في المخزن.
- إضافة سجل حركة محلي لكل منتج مع التاريخ والوقت.
- تسجيل حركات الشراء والاستهلاك والإضافة والتعديل.
- إضافة لوحة حالة للمخزن: إجمالي، طبيعي، منخفض ومنتهي.
- إدراج المنتجات المنتهية ضمن المنتجات المطلوب إضافتها لقائمة المقاضي.

### تحسينات
- تأكيد العملية قبل تحديث المخزن وحذف المنتجات المشتراة من القائمة.
- الحفاظ على البيانات القديمة المخزنة من المرحلة الأولى.
- تحديث GitHub Actions ليصدر Artifact باسم المرحلة الثانية.

## Sprint 2.6 — المرحلة الأولى

### الجديد
- إضافة شاشة مخزن المنزل.
- تسجيل الكمية الحالية والحد الأدنى والوحدة ومكان التخزين.
- أقسام للمخزن والثلاجة والفريزر والتنظيف والأطفال.
- تنبيه بصري للمنتجات التي وصلت إلى الحد الأدنى.
- بحث وتصفية حسب مكان التخزين والمنتجات الناقصة.
- زيادة أو تقليل الكمية مباشرة من البطاقة.
- إضافة جميع المنتجات الناقصة إلى قائمة مقاضي نشطة.
- حفظ بيانات المخزن محليًا والعمل دون إنترنت.
