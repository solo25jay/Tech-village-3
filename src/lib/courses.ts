import { supabase } from '@/lib/supabase'

export type CourseStatus = 'draft' | 'published' | 'archived'
export interface Course { id: string; org_id: string; title: string; summary: string | null; status: CourseStatus; created_by: string; created_at: string }
export interface ModuleRow { id: string; course_id: string; title: string; position: number }
export interface LessonRow { id: string; course_id: string; module_id: string; title: string; position: number }
export interface BlockRow { id: string; lesson_id: string; block_type: 'text' | 'video'; body: string | null; video_url: string | null; position: number }

// Row Level Security filters rows silently. For updates and deletes, "zero rows changed" means
// the server refused the change, so we surface it as a permission error instead of a fake success.
function mustAffect(rows: unknown[] | null) {
  if (!rows?.length) throw { code: '42501', message: 'You do not have permission to change this.' }
}
function check<T>(res: { data: T; error: unknown }): T {
  if (res.error) throw res.error
  return res.data
}

const COURSE_COLS = 'id, org_id, title, summary, status, created_by, created_at'

// ---- courses ----
export async function listCourses(orgId: string): Promise<Course[]> {
  return check(await supabase.from('courses').select(COURSE_COLS).eq('org_id', orgId).neq('status', 'archived').order('created_at', { ascending: false })) as Course[]
}
export async function getCourse(id: string): Promise<Course | null> {
  return check(await supabase.from('courses').select(COURSE_COLS).eq('id', id).maybeSingle()) as Course | null
}
export async function createCourse(orgId: string, title: string, summary: string): Promise<string> {
  const row = check(await supabase.from('courses').insert({ org_id: orgId, title: title.trim(), summary: summary.trim() || null }).select('id').single())
  return (row as { id: string }).id
}
export async function updateCourse(id: string, patch: { title?: string; summary?: string | null; status?: CourseStatus }) {
  mustAffect(check(await supabase.from('courses').update(patch).eq('id', id).select('id')))
}
export async function deleteCourse(id: string) {
  mustAffect(check(await supabase.from('courses').delete().eq('id', id).select('id')))
}

// ---- outline ----
export async function loadOutline(courseId: string): Promise<{ modules: ModuleRow[]; lessons: LessonRow[] }> {
  const [m, l] = await Promise.all([
    supabase.from('modules').select('id, course_id, title, position').eq('course_id', courseId).order('position'),
    supabase.from('lessons').select('id, course_id, module_id, title, position').eq('course_id', courseId).order('position'),
  ])
  return { modules: check(m) as ModuleRow[], lessons: check(l) as LessonRow[] }
}
const nextPos = (items: { position: number }[]) => (items.length ? Math.max(...items.map(i => i.position)) + 1 : 0)

export async function addModule(orgId: string, courseId: string, title: string, siblings: ModuleRow[]) {
  check(await supabase.from('modules').insert({ org_id: orgId, course_id: courseId, title: title.trim(), position: nextPos(siblings) }))
}
export async function renameModule(id: string, title: string) {
  mustAffect(check(await supabase.from('modules').update({ title: title.trim() }).eq('id', id).select('id')))
}
export async function deleteModule(id: string) {
  mustAffect(check(await supabase.from('modules').delete().eq('id', id).select('id')))
}
export async function addLesson(orgId: string, courseId: string, moduleId: string, title: string, siblings: LessonRow[]) {
  const row = check(await supabase.from('lessons').insert({ org_id: orgId, course_id: courseId, module_id: moduleId, title: title.trim(), position: nextPos(siblings) }).select('id').single())
  return (row as { id: string }).id
}
export async function renameLesson(id: string, title: string) {
  mustAffect(check(await supabase.from('lessons').update({ title: title.trim() }).eq('id', id).select('id')))
}
export async function deleteLesson(id: string) {
  mustAffect(check(await supabase.from('lessons').delete().eq('id', id).select('id')))
}

/** Swap positions with a neighbour. Two small updates; the editor reloads afterwards so a partial failure self-corrects. */
export async function swapPositions(table: 'modules' | 'lessons' | 'lesson_blocks', a: { id: string; position: number }, b: { id: string; position: number }) {
  mustAffect(check(await supabase.from(table).update({ position: b.position }).eq('id', a.id).select('id')))
  mustAffect(check(await supabase.from(table).update({ position: a.position }).eq('id', b.id).select('id')))
}

// ---- lesson blocks ----
export async function loadBlocks(lessonId: string): Promise<BlockRow[]> {
  return check(await supabase.from('lesson_blocks').select('id, lesson_id, block_type, body, video_url, position').eq('lesson_id', lessonId).order('position')) as BlockRow[]
}
export async function addBlock(orgId: string, courseId: string, lessonId: string, type: 'text' | 'video', content: { body?: string; video_url?: string }, siblings: BlockRow[]) {
  check(await supabase.from('lesson_blocks').insert({
    org_id: orgId, course_id: courseId, lesson_id: lessonId, block_type: type,
    body: type === 'text' ? content.body : null, video_url: type === 'video' ? content.video_url : null,
    position: nextPos(siblings),
  }))
}
export async function updateBlock(id: string, content: { body?: string; video_url?: string }) {
  mustAffect(check(await supabase.from('lesson_blocks').update(content).eq('id', id).select('id')))
}
export async function deleteBlock(id: string) {
  mustAffect(check(await supabase.from('lesson_blocks').delete().eq('id', id).select('id')))
}

// ---- enrolment and progress ----
export async function myEnrolledCourseIds(orgId: string, userId: string): Promise<Set<string>> {
  const rows = check(await supabase.from('enrolments').select('course_id').eq('org_id', orgId).eq('user_id', userId).eq('status', 'active')) as { course_id: string }[]
  return new Set(rows.map(r => r.course_id))
}
/** Enrol (or re-enrol after withdrawing) the signed-in user. */
export async function enrol(orgId: string, courseId: string, userId: string) {
  const res = await supabase.from('enrolments').insert({ org_id: orgId, course_id: courseId, user_id: userId })
  if (res.error?.code === '23505') { // already has a row: reactivate it
    mustAffect(check(await supabase.from('enrolments').update({ status: 'active' }).eq('course_id', courseId).eq('user_id', userId).select('id')))
    return
  }
  if (res.error) throw res.error
}
export async function withdraw(courseId: string, userId: string) {
  mustAffect(check(await supabase.from('enrolments').update({ status: 'withdrawn' }).eq('course_id', courseId).eq('user_id', userId).select('id')))
}
export async function completedLessonIds(courseId: string, userId: string): Promise<Set<string>> {
  const rows = check(await supabase.from('lesson_progress').select('lesson_id').eq('course_id', courseId).eq('user_id', userId)) as { lesson_id: string }[]
  return new Set(rows.map(r => r.lesson_id))
}
export async function markComplete(orgId: string, courseId: string, lessonId: string, userId: string) {
  const res = await supabase.from('lesson_progress').insert({ org_id: orgId, course_id: courseId, lesson_id: lessonId, user_id: userId })
  if (res.error && res.error.code !== '23505') throw res.error // already complete is fine
}
export async function unmarkComplete(lessonId: string, userId: string) {
  check(await supabase.from('lesson_progress').delete().eq('lesson_id', lessonId).eq('user_id', userId))
}
