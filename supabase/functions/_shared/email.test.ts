// Runs under plain Node 22+:  node --test supabase/functions/_shared/email.test.ts
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createResendProvider } from './email/resend.ts'
import { createEmailProvider } from './email/index.ts'
import { escapeHtml, cleanHeader, renderContactNotification, renderContactReceipt, renderWorkspaceWelcome } from './email/templates.ts'
import { validateContact } from './contact.ts'
import { deliver } from './deliver.ts'
import { formatEntitlements, annualSavingPercent, formatMoney } from '../../../src/lib/entitlements.ts'

const msg = { to: 'a@b.co', subject: 'Hi', html: '<p>Hi</p>', text: 'Hi', replyTo: 'r@b.co', idempotencyKey: 'k/1' }

function fakeFetch(status: number, payload: unknown, capture?: { url?: string; init?: RequestInit }) {
  return (async (url: string, init: RequestInit) => {
    if (capture) { capture.url = url; capture.init = init }
    return new Response(JSON.stringify(payload), { status })
  }) as unknown as typeof fetch
}

test('resend: sends the documented request shape', async () => {
  const cap: { url?: string; init?: RequestInit } = {}
  const p = createResendProvider({ apiKey: 're_test', from: 'TV <hi@x.co>', fetchImpl: fakeFetch(200, { id: 'abc' }, cap) })
  const r = await p.send(msg)
  assert.deepEqual(r, { ok: true, providerId: 'abc' })
  assert.equal(cap.url, 'https://api.resend.com/emails')
  const h = cap.init!.headers as Record<string, string>
  assert.equal(h.Authorization, 'Bearer re_test')
  assert.equal(h['Idempotency-Key'], 'k/1')
  const body = JSON.parse(cap.init!.body as string)
  assert.deepEqual(body.to, ['a@b.co'])
  assert.equal(body.from, 'TV <hi@x.co>')
  assert.equal(body.reply_to, 'r@b.co')
})

test('resend: truncates idempotency keys to 256 chars', async () => {
  const cap: { init?: RequestInit } = {}
  const p = createResendProvider({ apiKey: 'k', from: 'f', fetchImpl: fakeFetch(200, { id: '1' }, cap) })
  await p.send({ ...msg, idempotencyKey: 'x'.repeat(400) })
  assert.equal(((cap.init!.headers as Record<string, string>)['Idempotency-Key']).length, 256)
})

test('resend: classifies errors and never leaks the API key', async () => {
  const mk = (s: number) => createResendProvider({ apiKey: 're_SECRET', from: 'f', fetchImpl: fakeFetch(s, { message: 'bad' }) })
  const r429 = await mk(429).send(msg); assert.ok(!r429.ok && r429.retryable)
  const r500 = await mk(500).send(msg); assert.ok(!r500.ok && r500.retryable)
  const r422 = await mk(422).send(msg); assert.ok(!r422.ok && !r422.retryable)
  const boom = createResendProvider({ apiKey: 're_SECRET', from: 'f', fetchImpl: (async () => { throw new Error('re_SECRET exploded') }) as unknown as typeof fetch })
  const rn = await boom.send(msg)
  assert.ok(!rn.ok && rn.retryable && !rn.error.includes('re_SECRET'))
})

test('resend: a 200 without an id is not treated as success', async () => {
  const p = createResendProvider({ apiKey: 'k', from: 'f', fetchImpl: fakeFetch(200, {}) })
  const r = await p.send(msg); assert.ok(!r.ok)
})

test('provider factory fails loudly when misconfigured', () => {
  assert.throws(() => createEmailProvider({}), /RESEND_API_KEY/)
  assert.throws(() => createEmailProvider({ RESEND_API_KEY: 'k' }), /EMAIL_FROM/)
  assert.throws(() => createEmailProvider({ EMAIL_PROVIDER: 'nope' }), /Unknown/)
  assert.equal(createEmailProvider({ RESEND_API_KEY: 'k', EMAIL_FROM: 'f' }).name, 'resend')
  assert.equal(createEmailProvider({ EMAIL_PROVIDER: 'console' }).name, 'console')
})

test('templates: user input is escaped and cannot inject headers', () => {
  assert.equal(escapeHtml(`<script>"&'`), '&lt;script&gt;&quot;&amp;&#39;')
  assert.equal(cleanHeader('Hello\r\nBcc: evil@x.co'), 'Hello Bcc: evil@x.co')
  const out = renderContactNotification({ name: '<b>Eve</b>', email: 'e@x.co', topic: 'general', subject: 'Hi\r\nBcc: x@y.z', message: '<img src=x onerror=alert(1)>' })
  assert.ok(!out.html.includes('<img src=x'))
  assert.ok(!out.html.includes('<b>Eve</b>'))
  assert.ok(!/[\r\n]/.test(out.subject))
  assert.ok(out.text.includes('e@x.co'))
})

test('templates: welcome and receipt render with brand content', () => {
  const w = renderWorkspaceWelcome({ name: 'Ada Obi', workspaceName: 'Ada <Academy>', appUrl: 'https://app.example.com/' })
  assert.ok(w.html.includes('https://app.example.com/app'))
  assert.ok(w.html.includes('Ada &lt;Academy&gt;'))
  assert.ok(w.text.includes('https://app.example.com/app'))
  assert.ok(w.html.includes('Hi Ada'))
  const r = renderContactReceipt({ name: 'Chidi Eze' })
  assert.ok(r.html.includes('Thanks, Chidi'))
})

test('contact validation', () => {
  const good = { name: 'Ada', email: 'ADA@Example.com', topic: 'saas', subject: '', message: 'I want to run a school.' }
  const v = validateContact(good); assert.ok(v.ok && 'data' in v && v.data.email === 'ada@example.com' && v.data.topic === 'saas')
  assert.ok('spam' in (validateContact({ ...good, website: 'http://spam' }) as object))
  const bad = validateContact({ name: 'A', email: 'nope', message: 'short' })
  assert.ok(!bad.ok && 'errors' in bad && bad.errors.name && bad.errors.email && bad.errors.message)
  const t = validateContact({ ...good, topic: 'hack' }); assert.ok(t.ok && 'data' in t && t.data.topic === 'general')
  assert.ok(!validateContact({ ...good, email: 'a b@c.co' }).ok)
  assert.ok(!validateContact(null).ok)
  assert.ok(!validateContact({ ...good, message: 'x'.repeat(5001) }).ok)
})

function fakeDb(insertError?: { code: string }) {
  const calls: { op: string; payload?: unknown }[] = []
  const db = {
    from: () => ({
      insert: (payload: unknown) => { calls.push({ op: 'insert', payload }); return { select: () => ({ single: async () => insertError ? { data: null, error: insertError } : { data: { id: 'row1' }, error: null } }) } },
      update: (payload: unknown) => { calls.push({ op: 'update', payload }); return { eq: async () => ({ error: null }) } },
    }),
  }
  return { db, calls }
}

test('deliver: records queued then sent', async () => {
  const { db, calls } = fakeDb()
  const provider = { name: 'resend', send: async () => ({ ok: true as const, providerId: 'pid' }) }
  const r = await deliver(db, provider, msg, { template: 'workspace_welcome', org_id: 'o1' })
  assert.ok(r.ok)
  assert.equal((calls[0].payload as { status: string }).status, 'queued')
  assert.equal((calls[1].payload as { status: string; provider_message_id: string }).provider_message_id, 'pid')
})

test('deliver: records failures', async () => {
  const { db, calls } = fakeDb()
  const provider = { name: 'resend', send: async () => ({ ok: false as const, error: 'nope', retryable: false }) }
  const r = await deliver(db, provider, msg, { template: 't' })
  assert.ok(!r.ok)
  assert.deepEqual(calls[1].payload, { status: 'failed', error: 'nope' })
})

test('deliver: duplicate welcome is deduplicated and never sent', async () => {
  const { db } = fakeDb({ code: '23505' })
  let sent = false
  const provider = { name: 'resend', send: async () => { sent = true; return { ok: true as const, providerId: 'x' } } }
  const r = await deliver(db, provider, msg, { template: 'workspace_welcome', org_id: 'o1' })
  assert.ok(r.ok && 'deduped' in r)
  assert.equal(sent, false)
})

test('entitlement formatting', () => {
  const lines = formatEntitlements([
    { key: 'max_students', value: { limit: 10000 } },
    { key: 'max_sub_accounts', value: { limit: 0 } },   // legacy key: must be ignored now that sub-accounts are gone
    { key: 'storage_mb', value: { limit: 20000 } },
    { key: 'coding_labs', value: { enabled: true } },
    { key: 'custom_domains', value: { enabled: false } },
    { key: 'unknown_key', value: { limit: 1 } },
  ])
  assert.deepEqual(lines.map(l => [l.label, l.included]), [
    ['Up to 10,000 students', true], ['20 GB storage', true],
    ['Browser coding labs', true], ['Custom domain', false],
  ])
  assert.equal(annualSavingPercent(2500000, 25000000), 17)
  assert.equal(annualSavingPercent(0, 0), 0)
  assert.equal(formatMoney(0, 'NGN'), 'Free')
  assert.ok(formatMoney(2500000, 'NGN').includes('25,000'))
})
