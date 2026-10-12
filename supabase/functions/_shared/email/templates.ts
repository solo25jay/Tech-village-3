// Branded transactional templates. Colours match src/style.css (light theme values),
// because email clients ignore CSS variables and mostly ignore dark-mode hints.

export type TemplateName = 'contact_notification' | 'contact_receipt' | 'workspace_welcome'
export interface RenderedEmail { subject: string; html: string; text: string }

const NAVY = '#0B1D5B'
const BRAND = '#1F5BFF'
const SURFACE = '#F6F8FD'
const MUTED = '#5B6B95'
const LINE = '#DAE1F2'

export function escapeHtml(input: string): string {
  return input
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;')
}

/** Strip CR/LF and control characters so user input can never inject extra headers into a subject line. */
export function cleanHeader(input: string, max = 200): string {
  // deno-lint-ignore no-control-regex
  return input.replace(/[\u0000-\u001F\u007F]+/g, ' ').replace(/\s+/g, ' ').trim().slice(0, max)
}

interface LayoutOptions { preheader: string; heading: string; bodyHtml: string; cta?: { label: string; url: string }; siteUrl?: string }

function layout(o: LayoutOptions): string {
  const logo = o.siteUrl
    ? `<img src="${escapeHtml(o.siteUrl)}/brand/mark-on-white.png" width="40" alt="" style="display:inline-block;vertical-align:middle;margin-right:10px;border-radius:6px">`
    : ''
  const cta = o.cta
    ? `<p style="margin:28px 0 0"><a href="${escapeHtml(o.cta.url)}" style="display:inline-block;background:${BRAND};color:#ffffff;text-decoration:none;font-weight:600;padding:13px 22px;border-radius:10px">${escapeHtml(o.cta.label)}</a></p>`
    : ''
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"><title>${escapeHtml(o.heading)}</title></head>
<body style="margin:0;padding:0;background:${SURFACE};font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:${NAVY}">
<span style="display:none;max-height:0;overflow:hidden;opacity:0">${escapeHtml(o.preheader)}</span>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:${SURFACE};padding:28px 12px"><tr><td align="center">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border:1px solid ${LINE};border-radius:16px">
    <tr><td style="padding:26px 30px 0">${logo}<span style="font-size:19px;font-weight:800;vertical-align:middle;letter-spacing:-0.01em"><span style="color:${NAVY}">Tech</span> <span style="color:${BRAND}">Village</span></span></td></tr>
    <tr><td style="padding:22px 30px 30px">
      <h1 style="margin:0 0 14px;font-size:22px;line-height:1.25;color:${NAVY}">${escapeHtml(o.heading)}</h1>
      <div style="font-size:15px;line-height:1.6;color:${NAVY}">${o.bodyHtml}</div>${cta}
    </td></tr>
    <tr><td style="padding:16px 30px 24px;border-top:1px solid ${LINE};font-size:12px;line-height:1.5;color:${MUTED}">Tech Village. Learn, build, earn.</td></tr>
  </table>
</td></tr></table></body></html>`
}

const TOPIC_LABELS: Record<string, string> = {
  general: 'General question',
  programme: 'Programme interest',
  saas: 'Running my own platform',
  partnership: 'Partnership',
}
export const topicLabel = (t: string) => TOPIC_LABELS[t] ?? TOPIC_LABELS.general

export interface ContactVars { name: string; email: string; topic: string; subject: string; message: string; siteUrl?: string }
export interface ReceiptVars { name: string; siteUrl?: string }
export interface WelcomeVars { name: string; workspaceName: string; appUrl: string; siteUrl?: string }

export function renderContactNotification(v: ContactVars): RenderedEmail {
  const subject = cleanHeader(`${topicLabel(v.topic)}: ${v.subject || 'New message'} (${v.name})`)
  const row = (k: string, val: string) =>
    `<tr><td style="padding:4px 14px 4px 0;color:${MUTED};vertical-align:top">${k}</td><td style="padding:4px 0">${escapeHtml(val)}</td></tr>`
  const html = layout({
    preheader: `New message from ${v.name}`,
    heading: 'New contact message',
    siteUrl: v.siteUrl,
    bodyHtml: `<table role="presentation" cellpadding="0" cellspacing="0" style="font-size:14px">${row('Name', v.name)}${row('Email', v.email)}${row('Topic', topicLabel(v.topic))}${v.subject ? row('Subject', v.subject) : ''}</table>
      <p style="margin:18px 0 6px;color:${MUTED};font-size:13px">Message</p>
      <div style="white-space:pre-wrap;border-left:3px solid ${BRAND};padding:2px 0 2px 14px">${escapeHtml(v.message)}</div>
      <p style="margin:18px 0 0;color:${MUTED};font-size:13px">Reply to this email to answer ${escapeHtml(v.name)} directly.</p>`,
  })
  const text = `New contact message\n\nName: ${v.name}\nEmail: ${v.email}\nTopic: ${topicLabel(v.topic)}\n${v.subject ? `Subject: ${v.subject}\n` : ''}\n${v.message}\n`
  return { subject, html, text }
}

export function renderContactReceipt(v: ReceiptVars): RenderedEmail {
  const first = v.name.split(' ')[0] || 'there'
  const html = layout({
    preheader: 'We received your message',
    heading: `Thanks, ${first}. We got your message.`,
    siteUrl: v.siteUrl,
    bodyHtml: `<p style="margin:0 0 12px">A member of the Tech Village team will reply to this email address. If you did not send a message to us, you can ignore this email.</p>`,
  })
  const text = `Thanks, ${first}. We got your message.\n\nA member of the Tech Village team will reply to this email address. If you did not send a message to us, you can ignore this email.\n`
  return { subject: 'We received your message', html, text }
}

export function renderWorkspaceWelcome(v: WelcomeVars): RenderedEmail {
  const first = v.name.split(' ')[0] || 'there'
  const url = `${v.appUrl.replace(/\/+$/, '')}/app`
  const html = layout({
    preheader: `${v.workspaceName} is ready`,
    heading: 'Your workspace is ready',
    siteUrl: v.siteUrl,
    cta: { label: 'Open your workspace', url },
    bodyHtml: `<p style="margin:0 0 12px">Hi ${escapeHtml(first)}, <strong>${escapeHtml(v.workspaceName)}</strong> has been created and you are its owner.</p>
      <p style="margin:0">Your workspace is independent: it has its own settings, branding and plan. A good first step is adding your logo and organisation details in Organisation settings.</p>`,
  })
  const text = `Hi ${first},\n\n${v.workspaceName} has been created and you are its owner.\n\nOpen your workspace: ${url}\n`
  return { subject: cleanHeader(`${v.workspaceName} is ready on Tech Village`), html, text }
}
