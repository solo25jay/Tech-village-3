import { test } from 'node:test'
import assert from 'node:assert/strict'
import { parseVideoUrl, embedUrl } from './video.ts'

const YT = 'dQw4w9WgXcQ'

test('youtube: watch, short, embed and shorts links all normalise to one canonical form', () => {
  for (const url of [
    `https://www.youtube.com/watch?v=${YT}`,
    `https://youtube.com/watch?v=${YT}&t=42s&list=abc`,
    `https://m.youtube.com/watch?v=${YT}`,
    `https://youtu.be/${YT}?si=tracking`,
    `https://www.youtube.com/embed/${YT}`,
    `https://www.youtube.com/shorts/${YT}`,
  ]) {
    const v = parseVideoUrl(url)
    assert.equal(v?.canonical, `https://www.youtube.com/watch?v=${YT}`, url)
    assert.equal(v?.embed, `https://www.youtube-nocookie.com/embed/${YT}`, url)
  }
})

test('vimeo: page and player links normalise', () => {
  assert.equal(parseVideoUrl('https://vimeo.com/123456789')?.canonical, 'https://vimeo.com/123456789')
  assert.equal(parseVideoUrl('https://www.vimeo.com/123456789')?.embed, 'https://player.vimeo.com/video/123456789')
  assert.equal(parseVideoUrl('https://player.vimeo.com/video/123456789?h=abc')?.canonical, 'https://vimeo.com/123456789')
})

test('stored canonical links round-trip to an embed', () => {
  assert.equal(embedUrl(`https://www.youtube.com/watch?v=${YT}`), `https://www.youtube-nocookie.com/embed/${YT}`)
  assert.equal(embedUrl('https://vimeo.com/123456789'), 'https://player.vimeo.com/video/123456789')
})

test('rejects non-https, other hosts, lookalikes and credentials', () => {
  for (const url of [
    `http://www.youtube.com/watch?v=${YT}`,
    `https://evil.example/watch?v=${YT}`,
    `https://youtube.com.evil.example/watch?v=${YT}`,
    `https://evilyoutube.com/watch?v=${YT}`,
    `https://notyoutu.be/${YT}`,
    `https://youtube.com@evil.example/watch?v=${YT}`,
    `https://user:pw@www.youtube.com/watch?v=${YT}`,
    `https://www.youtube.com:8443/watch?v=${YT}`,
    'https://vimeo.com.evil.example/123456789',
    'javascript:alert(1)', 'data:text/html,<script>alert(1)</script>', 'ftp://youtu.be/dQw4w9WgXcQ',
    '', '   ', 'not a url',
  ]) assert.equal(parseVideoUrl(url), null, url)
})

test('rejects malformed or injected IDs', () => {
  for (const url of [
    'https://www.youtube.com/watch?v=short',
    `https://www.youtube.com/watch?v=${YT}x`,
    'https://www.youtube.com/watch?v="><script>alert(1)</script>',
    'https://www.youtube.com/watch',
    'https://www.youtube.com/channel/UC1234567890',
    'https://youtu.be/',
    'https://vimeo.com/abcdef',
    'https://vimeo.com/12345',
    'https://vimeo.com/channels/staffpicks/123456789',
    'https://player.vimeo.com/video/12%2e5',
  ]) assert.equal(parseVideoUrl(url), null, url)
})

test('the embed address is built only from the validated ID', () => {
  const v = parseVideoUrl(`https://youtu.be/${YT}?autoplay=1&evil=%22%3E`)
  assert.ok(v)
  assert.match(v.embed, /^https:\/\/www\.youtube-nocookie\.com\/embed\/[A-Za-z0-9_-]{11}$/)
  assert.equal(v.canonical.includes('autoplay'), false)
})

test('canonical output satisfies the database CHECK pattern', () => {
  const db = /^https:\/\/(www\.)?(youtube\.com\/watch\?v=[A-Za-z0-9_-]{11}|youtu\.be\/[A-Za-z0-9_-]{11}|vimeo\.com\/[0-9]{6,12})$/i
  for (const url of [`https://youtu.be/${YT}`, 'https://player.vimeo.com/video/123456789', `https://www.youtube.com/embed/${YT}`]) {
    const v = parseVideoUrl(url)
    assert.ok(v && db.test(v.canonical), url)
  }
})
