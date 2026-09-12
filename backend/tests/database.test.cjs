const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {PGlite}=require('@electric-sql/pglite');

// Real PostgreSQL SQL/RLS engine with a minimal Supabase auth schema shim.
// This does not simulate GoTrue, network Realtime delivery, or concurrent sessions.
test('migration: owner isolation, atomic turns, leases, stops and soft deletion',async()=>{
  const db=new PGlite();
  try {
    await db.exec(`create role anon; create role authenticated;
      create schema auth; create table auth.users(id uuid primary key);
      create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
      grant usage on schema public,auth to authenticated,anon;
      grant execute on function auth.uid() to authenticated,anon;`);
    const migration=fs.readFileSync(path.join(__dirname,'../../supabase/migrations/202609100001_chat.sql'),'utf8');
    // Publication delivery needs Supabase Realtime, not the embedded engine.
    await db.exec(migration.replace('alter publication supabase_realtime add table public.conversations, public.messages;',''));
    const a='10000000-0000-4000-8000-000000000001',b='10000000-0000-4000-8000-000000000002';
    const room='20000000-0000-4000-8000-000000000001',run='30000000-0000-4000-8000-000000000001',msg='40000000-0000-4000-8000-000000000001';
    const run2='30000000-0000-4000-8000-000000000002',msg2='40000000-0000-4000-8000-000000000002';
    await db.query('insert into auth.users values ($1),($2)',[a,b]);
    const as=async(user)=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[user]);await db.exec('set role authenticated');};
    const begin=(id=run,mid=msg)=>db.query('select public.begin_chat($1,$2,$3,$4,$5) as result',[room,id,mid,'hello','model']);
    const save=(status,content='partial',id=run)=>db.query('select public.save_chat($1,$2,$3,$4) as result',[id,content,'reasoning',status]);
    await as(a);
    await db.query('insert into public.conversations(id,title,model) values($1,$2,$3)',[room,'room','model']);
    assert.equal((await begin()).rows[0].result.started,true);
    assert.equal((await begin()).rows[0].result.started,false);
    assert.equal((await db.query('select count(*)::int as n from public.messages')).rows[0].n,2);
    await assert.rejects(begin(run2,msg2),/ROOM_BUSY/);
    await assert.rejects(db.query('update public.messages set content=$1',['forged']),/permission denied/);
    await assert.rejects(db.query('update public.chat_runs set lease_until=now()'),/permission denied/);
    await assert.rejects(db.query('update public.conversations set user_id=$1',[b]),/permission denied/);
    await as(b);
    for(const table of ['conversations','messages','chat_runs']) assert.equal((await db.query('select * from public.'+table)).rows.length,0);
    await assert.rejects(begin(),/ROOM_NOT_FOUND/);
    await assert.rejects(save('completed'),/ROOM_NOT_FOUND/);
    await assert.rejects(db.query('select public.stop_chat($1)',[run]),/ROOM_NOT_FOUND/);
    await assert.rejects(db.query('select public.delete_conversation($1)',[room]),/ROOM_NOT_FOUND/);
    assert.equal((await db.query('update public.conversations set title=$1 where id=$2 returning id',['hacked',room])).rows.length,0);
    await assert.rejects(db.query('insert into public.conversations(id,user_id,title,model) values(gen_random_uuid(),$1,$2,$3)',[a,'fake','model']),/row-level security/);
    await as(a);
    await save('streaming','longer partial');
    await save('stopped','short');
    assert.equal((await save('completed','late write')).rows[0].result,'stopped');
    assert.equal((await db.query("select content from public.messages where role='assistant'")).rows[0].content,'longer partial');
    await begin(run2,msg2);
    await assert.rejects(save('completed','',run2),/EMPTY_ANSWER/);
    await db.exec('reset role');
    await db.query("update public.chat_runs set lease_until=now()-interval '1 second' where id=$1",[run2]);
    await as(a);
    await db.query('select public.recover_chat($1)',[room]);
    assert.equal((await save('completed','too late',run2)).rows[0].result,'interrupted');
    assert.deepEqual((await db.query('select sequence::int from public.messages order by sequence')).rows.map(r=>r.sequence),[1,2,3,4]);
    await db.query('select public.delete_conversation($1)',[room]);
    assert.equal((await db.query('select * from public.messages')).rows.length,0);
    assert.ok((await db.query('select deleted_at from public.conversations')).rows[0].deleted_at);
    await assert.rejects(save('completed'),/ROOM_NOT_FOUND/);
    await assert.rejects(begin(),/ROOM_NOT_FOUND/);
    await db.exec('reset role; set role anon');
    await assert.rejects(db.query('select * from public.conversations'),/permission denied/);
    await assert.rejects(begin(),/permission denied/);
  } finally {await db.close();}
});
