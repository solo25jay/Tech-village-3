export interface EntitlementRow { key: string; value: { limit?: number; enabled?: boolean } }
export interface FeatureLine { key: string; label: string; included: boolean }

const n = (v: number) => v.toLocaleString('en')
const storage = (mb: number) => (mb >= 1000 ? `${n(Math.round(mb / 1000))} GB storage` : `${n(mb)} MB storage`)

// Display order and wording live here; the numbers come from the database so plans
// can be edited without a code change.
const LIMITS: Array<[string, (v: number) => string, string]> = [
  ['max_students', v => `Up to ${n(v)} students`, 'Students'],
  ['max_instructors', v => `Up to ${n(v)} ${v === 1 ? 'instructor' : 'instructors'}`, 'Instructors'],
  ['max_courses', v => `Up to ${n(v)} courses`, 'Courses'],
  ['storage_mb', storage, 'Storage'],
]
const FLAGS: Array<[string, string]> = [
  ['coding_labs', 'Browser coding labs'],
  ['custom_branding', 'Custom branding'],
  ['custom_domains', 'Custom domain'],
]

export function formatEntitlements(rows: EntitlementRow[]): FeatureLine[] {
  const byKey = new Map(rows.map(r => [r.key, r.value]))
  const lines: FeatureLine[] = []
  for (const [key, fmt, absentLabel] of LIMITS) {
    const v = byKey.get(key)
    if (v?.limit === undefined) continue
    lines.push(v.limit > 0
      ? { key, label: fmt(v.limit), included: true }
      : { key, label: absentLabel, included: false })
  }
  for (const [key, label] of FLAGS) {
    const v = byKey.get(key)
    if (v === undefined) continue
    lines.push({ key, label, included: v.enabled === true })
  }
  return lines
}

/** Percentage saved by paying yearly, or 0 when there is no saving. Computed, never hard-coded. */
export function annualSavingPercent(monthMinor: number, yearMinor: number): number {
  if (monthMinor <= 0 || yearMinor <= 0) return 0
  const pct = Math.round((1 - yearMinor / (monthMinor * 12)) * 100)
  return pct > 0 ? pct : 0
}

export function formatMoney(minor: number, currency: string): string {
  if (minor <= 0) return 'Free'
  return new Intl.NumberFormat('en-NG', { style: 'currency', currency, maximumFractionDigits: 0 }).format(minor / 100)
}
