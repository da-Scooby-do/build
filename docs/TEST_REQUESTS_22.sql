-- ============================================================================
-- مداد — 22 طلبًا تجريبيًا لمعاينة قسم «أحدث طلبات العملاء»
-- ----------------------------------------------------------------------------
-- كل طلب هنا موسوم بسطر «اختبار: نعم» داخل customer_notes، ورقمه يبدأ بـ TEST-REQ-.
-- لا تظهر للزوار أبدًا: الدالة public_requests تخفيها، ولا تظهر إلا في وضع
-- المعاينة https://www.midad-ksa.com/?preview=1
-- (تظهر في لوحة التحكم ضمن الطلبات — احذفها بالقسم ٢ أدناه بعد المعاينة.)
-- ============================================================================

-- ١) الإضافة
insert into public.orders (order_number, user_id, status, payment_status, subtotal, vat_amount, delivery_fee, total, customer_notes, created_at)
select
  'TEST-REQ-' || lpad(t.n::text, 2, '0'),
  null,
  t.st::public.order_status,
  'pending',
  0, 0, 0, 0,
  concat_ws(E'\n',
    'الفئة: ' || t.cat,
    case when t.items is not null then 'المعدات المطلوبة: ' || t.items end,
    'الكمية: ' || t.qty,
    'الاسم: عميل تجريبي',
    'الجوال: 0500000000',
    'المدينة: ' || t.city,
    'المطلوب بحلول: ' || to_char((now() + (t.need_days || ' days')::interval)::date, 'YYYY-MM-DD'),
    'التفاصيل: طلب تجريبي لمعاينة الموقع',
    'اختبار: نعم'),
  now() - (t.age_hours || ' hours')::interval
from (values
  ( 1, 'حديد تسليح',            null,                         '50 طن',          'الرياض',          30,   2, 'pending'),
  ( 2, 'خرسانة جاهزة',          null,                         '120 م³',         'جدة',             14,   5, 'pending'),
  ( 3, 'معدات ثقيلة',           'بوكلين / حفار',              'معدة واحدة',     'المدينة المنورة', 30,   9, 'pending'),
  ( 4, 'طوب',                   null,                         '100,000 قطعة',   'الدمام',          7,   14, 'pending'),
  ( 5, 'سقالات وشدّات',         null,                         '3000 متر',       'مكة المكرمة',     1,   20, 'pending'),
  ( 6, 'أسمنت',                 null,                         '80 طن',          'بريدة',           21,  26, 'pending'),
  ( 7, 'معدات ثقيلة',           'شيول، قلابات',               '3 معدات',        'أبها',            30,  31, 'confirmed'),
  ( 8, 'بلاط وسيراميك ورخام',   null,                         '1,500 م²',       'تبوك',            14,  38, 'pending'),
  ( 9, 'أخشاب',                 null,                         '40 م³',          'الطائف',          10,  45, 'pending'),
  (10, 'سباكة وكهرباء',         null,                         'مشروع 12 فيلا',  'الخبر',           20,  52, 'pending'),
  (11, 'حديد تسليح',            null,                         '220 طن',         'خميس مشيط',       45,  60, 'delivered'),
  (12, 'جبس وجبس بورد',         null,                         '2,000 لوح',      'حائل',            12,  70, 'pending'),
  (13, 'أبواب ونوافذ وألمنيوم', null,                         '64 باب',         'الهفوف',          25,  80, 'pending'),
  (14, 'تكييف وتهوية',          null,                         '30 وحدة',        'الجبيل',          18,  92, 'confirmed'),
  (15, 'خرسانة جاهزة',          null,                         '350 م³',         'ينبع',            9,  100, 'pending'),
  (16, 'معدات سلامة ووقاية',    null,                         '200 طقم',        'نجران',           6,  115, 'pending'),
  (17, 'معدات ثقيلة',           'رافعات برجية',               'رافعة واحدة',    'الرياض',          40, 128, 'pending'),
  (18, 'طوب',                   null,                         '25,000 قطعة',    'عنيزة',           10, 140, 'delivered'),
  (19, 'أسمنت',                 null,                         '600 كيس',        'جازان',           5,  155, 'pending'),
  (20, 'حديد تسليح',            null,                         '15 طن',          'عرعر',            14, 170, 'pending'),
  (21, 'بلاط وسيراميك ورخام',   null,                         '800 م²',         'القطيف',          20, 190, 'pending'),
  (22, 'سقالات وشدّات',         null,                         '1,200 متر',      'الباحة',          15, 210, 'pending')
) as t(n, cat, items, qty, city, need_days, age_hours, st)
on conflict (order_number) do nothing;

-- ٢) الحذف بعد المعاينة
-- delete from public.order_items where order_id in (select id from public.orders where order_number like 'TEST-REQ-%');
-- delete from public.orders where order_number like 'TEST-REQ-%';
