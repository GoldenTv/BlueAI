# BlueAI Cloudflare Workers Backend

Backend API สำหรับ BlueAI พัฒนาด้วย **Cloudflare Workers** ร่วมกับ **Vercel AI SDK** รองรับ Real-time Text Streaming และเชื่อมต่อไปยัง Gateway `https://ai.psu.blue/v1` ได้อย่างราบรื่นโดยไม่ถูกบล็อก IP

---

## ระบบบัญชีและประวัติ
Worker ตรวจ session กับ Supabase Auth แล้วอ่าน/บันทึกข้อความผ่าน RPC ด้วย token ผู้ใช้
ดู [คู่มือตั้งค่า Supabase/Google](../docs/SUPABASE_SETUP.md) ก่อนใช้งาน

---

## ตัวแปรสภาพแวดล้อม (Environment Variables)

กำหนดใน `wrangler.toml`:

| ตัวแปร | ชนิด | คำอธิบาย |
|---|---|---|
| `AI_BASE_URL` | Variable | Base URL: `https://ai.psu.blue/v1` (ตั้งไว้ใน wrangler.toml แล้ว) |
| `SUPABASE_URL` | Variable | URL ของ project เดียวกับแอป |
| `SUPABASE_PUBLISHABLE_KEY` | Variable | Publishable key ไม่ใช่ service-role key |
| `ALLOWED_ORIGINS` | Variable | Exact web origins คั่นด้วย comma เช่น http://localhost:3000 |

แอปส่ง Supabase token ใน `Authorization: Bearer <access token>` และ AI key ใน
`X-AI-API-Key` เฉพาะ AI key เท่านั้นที่ถูกส่งให้ gateway และไม่เขียน key ลงฐานข้อมูล/log

---

## 1. การทดสอบในเครื่อง (Local Development)

1. เข้าโฟลเดอร์ `backend`:
   ```bash
   cd backend
   ```
2. คัดลอก `.dev.vars.example` เป็น `.dev.vars` แล้วกรอก URL/key และ origins ก่อนรัน:
   ```bash
   npm run dev
   ```
   API จะพร้อมทำงานที่ `http://localhost:8787`

---

## 2. การ Deploy ขึ้น Cloudflare Workers (Production)

1. เข้าสู่ระบบ Cloudflare (ทำครั้งแรกเพียงครั้งเดียว):
   ```bash
   npx wrangler login
   ```
2. ตั้งค่า Supabase URL/key และ origins บน Worker production แยกต่างหาก (`.dev.vars` ไม่ถูก deploy) แล้วรัน:
   ```bash
   npm run deploy
   ```
3. คุณจะได้รับ URL สำหรับใช้งานทันที เช่น:
   ```text
   https://blueai-backend.<your-subdomain>.workers.dev
   ```
   *(นำ URL นี้ไปใส่ในแอป Flutter ผ่านปุ่มตั้งค่า ⚙ พร้อมระบุ API Key ของคุณ)*

## API v1

`POST /v1/chat` รับ JSON `conversationId`, `requestId`, `messageId` (UUID), `prompt`, `model`
จองห้อง/บันทึก user กับ assistant placeholder แบบ atomic ผ่าน `begin_chat`
request ID เดิมคืน 409 `REQUEST_EXISTS` โดยไม่เรียก AI ซ้ำ ห้อง busy คืน `ROOM_BUSY`
โหลดประวัติ 24 ข้อความ completed ที่ไม่ว่างจากฐานข้อมูล โดยไม่เอา reasoning/error เข้า context

SSE ส่ง `text`, `thinking`, `error` และส่ง `[DONE]` หลังฐานข้อมูลยืนยัน completed เท่านั้น
checkpoint อย่างมากทุก 2 วินาที และ heartbeat ต่อ lease ระหว่าง idle ทุก 20 วินาที
lease 120 วินาที; upstream idle timeout 90 วินาที; disconnect พยายามเก็บ partial ผ่าน waitUntil
เปิด/refetch ห้องหรือเริ่ม turn ใหม่จะ recover request หมดอายุเป็น interrupted

`POST /v1/chat/{requestId}/stop` ใช้ Supabase Authorization header รับ optional JSON
`content`, `reasoning` เพื่อเก็บ partial ก่อน abort stream ไม่ต้องส่ง AI key
terminal state ป้องกัน late writes และห้อง soft-deleted ไม่รับการเขียนอีก
API เดิม `POST /` ปิดแล้ว (404)

รัน `npm run build` และ `npm test`: ใช้ AI SDK จริงกับ HTTP mock และ PostgreSQL/PGlite
ทดสอบ RLS โดยไม่ต้องมี cloud credentials การทดสอบ OAuth/Realtime/สองอุปกรณ์จริงแยกตามคู่มือ
