export interface CloudEnv { SUPABASE_URL?: string; SUPABASE_PUBLISHABLE_KEY?: string; }
export class ApiError extends Error {
  constructor(public code: string, message: string, public status = 500) { super(message); }
}
export class CloudStore {
  private headers: Record<string, string>;
  private url: string;
  constructor(env: CloudEnv, token: string) {
    if (!env.SUPABASE_URL || !env.SUPABASE_PUBLISHABLE_KEY) throw new ApiError('NOT_CONFIGURED', 'ยังไม่ได้ตั้งค่า Supabase บน Worker', 503);
    this.url = env.SUPABASE_URL.replace(/\/$/, '');
    this.headers = { apikey: env.SUPABASE_PUBLISHABLE_KEY, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
  }
  async call(path: string, body?: unknown): Promise<any> {
    let response: Response;
    try {
      response = await fetch(`${this.url}${path}`, {
        method: body === undefined ? 'GET' : 'POST', headers: this.headers,
        body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(12000),
      });
    } catch { throw new ApiError('STORAGE_UNAVAILABLE', 'ติดต่อฐานข้อมูลไม่ได้ กรุณาลองใหม่', 503); }
    const result: any = await response.json().catch(() => ({}));
    if (!response.ok) {
      const message = String(result.message ?? result.msg ?? '');
      if (response.status === 401) throw new ApiError('AUTH_EXPIRED', 'กรุณาเข้าสู่ระบบอีกครั้ง', 401);
      const errors: Record<string,string> = {ROOM_NOT_FOUND:'ไม่พบห้องหรือไม่มีสิทธิ์เข้าถึง',ROOM_BUSY:'ห้องนี้กำลังตอบจากอีกอุปกรณ์',REQUEST_CONFLICT:'รหัสคำขอนี้ถูกใช้แล้ว',INVALID_INPUT:'ข้อมูลไม่ถูกต้อง',EMPTY_ANSWER:'โมเดลยังไม่ส่งคำตอบหลัก'};
      for (const [code, detail] of Object.entries(errors)) {
        if (message.includes(code)) throw new ApiError(code, detail, code === 'ROOM_NOT_FOUND' ? 404 : code === 'INVALID_INPUT' ? 400 : 409);
      }
      throw new ApiError('STORAGE_UNAVAILABLE', 'ไม่สามารถบันทึกหรือโหลดบทสนทนาได้', 503);
    }
    return result;
  }
  async authenticate(): Promise<string> {
    const user = await this.call('/auth/v1/user');
    if (typeof user.id !== 'string') throw new ApiError('AUTH_EXPIRED', 'กรุณาเข้าสู่ระบบอีกครั้ง', 401);
    return user.id;
  }
  rpc(name: string, body: unknown) { return this.call(`/rest/v1/rpc/${name}`, body); }
  async history(room: string) {
    const rows = await this.call(`/rest/v1/messages?conversation_id=eq.${room}&status=eq.completed&content=neq.&select=role,content&order=sequence.desc&limit=24`);
    return rows.reverse() as Array<{ role: 'user' | 'assistant'; content: string }>;
  }
}
