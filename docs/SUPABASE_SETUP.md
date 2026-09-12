# ตั้งค่า BlueAI: Supabase + Google + Cloudflare

## 1. Supabase project

สร้าง project ในบัญชี Supabase ของคุณ และคัดลอก Project URL กับ **publishable key**
จากหน้าตั้งค่า API จากนั้นเปิด SQL Editor แล้วรัน
`supabase/migrations/202609100001_chat.sql` ทั้งไฟล์หนึ่งครั้งใน project ใหม่
ตรวจว่ามี `conversations`, `messages`, `chat_runs` และเปิด RLS ทุกตาราง
Migration เพิ่ม conversations/messages เข้า publication `supabase_realtime` แล้ว

อย่าใส่ service-role key, database password หรือ Google client secret ในแอปหรือ Worker
Worker ใช้ token ผู้ใช้กับ publishable key; RPC SECURITY DEFINER ตรวจ `auth.uid()`
ทุกครั้งเพื่อจัดสรรลำดับและจองห้องแบบ atomic โดยไม่รับ owner จาก client
การอ่านและ subscription ใช้ RLS และปิดสิทธิ์เขียน message/lease โดยตรง

## 2. Google OAuth

1. ใน Google Cloud/Google Auth Platform ตั้ง project, Branding, Audience และ consent screen
2. ช่วง Testing เพิ่มบัญชีทดสอบใน Test users ใช้ scopes openid, email และ profile
3. สร้าง OAuth client ชนิด **Web application** สำหรับ browser OAuth ผ่าน Supabase
4. Authorized redirect URI ของ Google ใช้ callback ที่ Supabase Google provider แสดง เช่น `https://YOUR_PROJECT.supabase.co/auth/v1/callback`
5. ใส่ Client ID และ Client Secret ใน **Supabase Authentication → Providers → Google** แล้วเปิด provider
6. ปิด provider อื่นที่ไม่ใช้ รวมถึง Anonymous Sign-In

Secret อยู่ใน provider เท่านั้น ดู [Google login](https://supabase.com/docs/guides/auth/social-login/auth-google)

### Android: ตัวเลือกบัญชี Google ในแอป

Android ใช้ `google_sign_in` (Credential Manager) แล้วส่ง ID token ให้ Supabase
ด้วย `signInWithIdToken` เพื่อใช้บัญชีและประวัติออนไลน์เดิม ไม่มี browser fallback
เมื่อยกเลิกหรือเข้าสู่ระบบไม่สำเร็จ ส่วนเว็บ/iOS/desktop ยังใช้ OAuth เดิม
หน้าตาตัวเลือกบัญชีขึ้นอยู่กับ Android และ Google Play services ของอุปกรณ์

1. ใช้ Web OAuth Client ID ของ Google project เดียวกับที่ตั้งใน Supabase
   ใส่ `GOOGLE_WEB_CLIENT_ID` ใน `config/dev.json` (ไม่ใช่ Client Secret)
2. สร้าง Android OAuth client ใน Google Cloud โดยใช้ package `com.example.blue_app`
   และ SHA-1 ของ signing certificate ที่ใช้ติดตั้งแอป ทะเบียนต้องตรงทั้ง debug/release
   และ Play App Signing หากเผยแพร่ผ่าน Play Store
3. ตรวจว่า Supabase Google provider ยอมรับ Web Client ID นี้
4. หยุดแอปแล้ว build/run ใหม่ด้วย `--dart-define-from-file=config/dev.json`
   การเพิ่ม native plugin ใช้ Hot Reload อย่างเดียวไม่ได้

ไม่ต้องใช้ Firebase หรือ google-services.json เมื่อส่ง Web Client ID ผ่าน
`serverClientId` ตามวิธีนี้ ดู [Android integration](https://pub.dev/packages/google_sign_in_android)
หากเลือกบัญชีแล้วปิดกลับมาซ้ำ ๆ ให้ตรวจ package, SHA-1 และ Web Client ID
เพราะ Credential Manager อาจรายงาน configuration ผิดเป็นการยกเลิกได้

ทดสอบบน Android ที่มี Google Play services: เลือกบัญชีแล้วเห็นประวัติเดิม,
ยกเลิกแล้วกดใหม่ได้, กลับจาก account picker แล้วปุ่มยังไม่รับคำขอซ้อน,
ออกจากระบบแล้วเลือกบัญชีอื่นได้ และปิดเปิดแอปแล้ว session ยังอยู่

บน Windows หาก `flutter pub get` แจ้ง symlink support ให้เปิด Developer Mode
แล้วรันคำสั่งอีกครั้งก่อน build

## 3. Redirect allowlist

Supabase Authentication → URL Configuration: ตั้ง Site URL เป็นเว็บของคุณ
(พัฒนาใช้ `http://localhost:3000`) และเพิ่ม redirect URLs แบบเจาะจง:

- `blueai://auth/callback` สำหรับ Android/iOS
- `http://localhost:3000` สำหรับ Flutter web
- HTTPS origin ที่เป็นเจ้าของเมื่อใช้เว็บจริง

Mobile callback เพิ่มใน AndroidManifest.xml และ iOS Info.plist แล้ว
SDK ใช้ PKCE และจัดการ code exchange/refresh; session และ verifier ใช้ secure storage
เว็บต้องใช้ localhost หรือ HTTPS และใช้ origin/port เดิมข้าม OAuth redirect
ดู [redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls)

## 4. Worker และแอป

คัดลอก `backend/.dev.vars.example` เป็น `.dev.vars` แล้วกรอก Supabase URL/key
ตั้ง `ALLOWED_ORIGINS=http://localhost:3000` สำหรับเว็บพัฒนา

```powershell
cd D:\Blue_AI\backend
npm ci
npm run dev -- --ip 0.0.0.0
```

คัดลอก `config/dev.example.json` เป็น `config/dev.json` กรอก URL/key ชุดเดียวกัน
เปลี่ยน IP Worker ให้ตรงคอมพิวเตอร์ แล้วรัน:

```powershell
cd D:\Blue_AI
flutter run --dart-define-from-file=config/dev.json
```

Android Studio: Run/Debug Configurations → Flutter → main.dart → **Additional run args**:

```text
--dart-define-from-file=config/dev.json
```

กด Apply แล้ว Run ครั้งต่อไปได้โดยไม่ต้องกรอก URL ซ้ำ เว็บใช้
`flutter run -d chrome --web-port=3000 --dart-define-from-file=config/dev.json`
หากเคยบันทึก Backend URL ในแอป ค่านั้นมีลำดับเหนือ dart-define ให้แก้ในหน้าตั้งค่าด้วย
มือถือจริงใช้ LAN IP; Android emulator ใช้ `10.0.2.2:8787` ได้
Firewall ต้องอนุญาตพอร์ตในเครือข่ายทดสอบ HTTP ไม่เข้ารหัสจึงใช้เฉพาะพัฒนา
deploy จริงเปลี่ยนเป็น HTTPS และปิด `BLUEAI_ALLOW_INSECURE_HTTP`
เปลี่ยน dart-defines แล้วต้องหยุดและ Run ใหม่

## 5. การตรวจสอบ

```powershell
flutter analyze --no-pub
flutter test --no-pub
cd backend
npm run build
npm test
```

SQL tests ใช้ PostgreSQL ผ่าน PGlite พร้อม shim auth.uid(): ทดสอบบัญชี A/B,
ปลอม owner, การเขียน message/lease โดยตรง, duplicate request, busy, ลำดับข้อความ,
expiry, stopped partial และ late writes หลังลบ โดยไม่ใช้ credentials จริง
ไม่ได้จำลองบริการ OAuth/Realtime หรือ lock จากหลาย connection

ก่อน release ให้ทดสอบสองบัญชีและสองอุปกรณ์ใน project ทดสอบ:

1. Login/ยกเลิก/ลองใหม่; เปิดแอปใหม่ session ยังอยู่; ทดสอบ refresh และ revoke session
2. สร้าง/เปลี่ยนชื่อ/ปักหมุด/ลบสะท้อนอีกเครื่องที่ใช้บัญชีเดียวกัน
3. ส่งพร้อมกันห้องเดียว ต้องเริ่ม AI ได้เพียงหนึ่ง request; request ID เดิมต้องไม่เพิ่ม turn
4. Token B กับ room/request ของ A ต้องอ่าน/เขียน/หยุด/ลบไม่ได้ และ subscription ไม่ได้รับข้อมูล A
5. Stop/เปลี่ยนห้อง/ลบระหว่างตอบ เก็บ partial และไม่มีคำตอบข้ามห้อง
6. ตัดเน็ต/ปิดแอปกลางตอบ รอเกิน 120 วินาทีแล้วเปิดห้อง สถานะเป็น interrupted ไม่ใช่ completed
7. Offline อ่านข้อมูลใน memory/พิมพ์ร่างได้ แต่ส่งและแก้ข้อมูล cloud ไม่ได้; reconnect ไม่ส่งซ้ำอัตโนมัติ
8. Sign out A แล้ว login B ไม่เห็นข้อความ/ร่าง/key ของ A; เครื่องใหม่ต้องกรอก key ใหม่
9. ประวัติเกิน 50 ข้อความและรายการเกิน 30 ห้องเลื่อนโหลดเพิ่มได้; กลับจาก background แล้วข้อมูลตรงกัน

## 6. เปิดใช้งาน

Apply migration ใน project เป้าหมาย ตั้ง Supabase URL/key และ exact web origins
ของ production บน Cloudflare (`.dev.vars` ไม่ถูก deploy) แล้ว deploy Worker ก่อนแอปใหม่
API แบบไม่ล็อกอินถูกปิดแล้ว แอปรุ่นเก่าต้องอัปเดตเพื่อใช้งานต่อ
สำรองฐานข้อมูลก่อนเปลี่ยน schema ภายหลัง ไม่ลบตารางที่มีประวัติผู้ใช้เพื่อย้อนรุ่น
ยังต้องยืนยัน OAuth/Realtime/Android/iOS บนอุปกรณ์จริงก่อน production
Build iOS ต้องใช้ macOS/Xcode

อ้างอิง [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security) และ
[Realtime](https://supabase.com/docs/guides/realtime/subscribing-to-database-changes)
