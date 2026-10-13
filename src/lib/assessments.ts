import { supabase } from '@/lib/supabase'

export type AssessmentKind = 'quiz' | 'assignment'
export interface Assessment {
  id: string; org_id: string; course_id: string; kind: AssessmentKind; title: string; instructions: string | null
  status: 'draft' | 'published'; pass_mark: number; max_attempts: number | null; max_points: number; due_at: string | null; position: number
}
export interface Question { id: string; assessment_id: string; position: number; prompt: string; points: number }
export interface Option { id: string; question_id: string; position: number; label: string }
export interface Attempt { id: string; assessment_id: string; user_id: string; attempt_no: number; score_percent: number; passed: boolean; submitted_at: string }
export interface Submission {
  id: string; assessment_id: string; user_id: string; body: string; status: 'submitted' | 'graded'
  points: number | null; feedback: string | null; submitted_at: string; graded_at: string | null
}
export interface QuizResult { attempt_no: number; score_percent: number; passed: boolean; results: Record<string, boolean> }

// Row Level Security filters rows silently: zero rows changed means the server refused the change.
function mustAffect(rows: unknown[] | null) {
  if (!rows?.length) throw { code: '42501', message: 'You do not have permission to change this.' }
}
function check<T>(res: { data: T; error: unknown }): T {
  if (res.error) throw res.error
  return res.data
}
const nextPos = (items: { position: number }[]) => (items.length ? Math.max(...items.map(i => i.position)) + 1 : 0)

const A_COLS = 'id, org_id, course_id, kind, title, instructions, status, pass_mark, max_attempts, max_points, due_at, position'

// ---- assessments ----
export async function listAssessments(courseId: string): Promise<Assessment[]> {
  return check(await supabase.from('assessments').select(A_COLS).eq('course_id', courseId).order('position').order('created_at')) as Assessment[]
}
export async function getAssessment(id: string): Promise<Assessment | null> {
  return check(await supabase.from('assessments').select(A_COLS).eq('id', id).maybeSingle()) as Assessment | null
}
export async function createAssessment(orgId: string, courseId: string, kind: AssessmentKind, title: string, siblings: Assessment[]): Promise<string> {
  const row = check(await supabase.from('assessments').insert({ org_id: orgId, course_id: courseId, kind, title: title.trim(), position: nextPos(siblings) }).select('id').single())
  return (row as { id: string }).id
}
export async function updateAssessment(id: string, patch: Partial<Pick<Assessment, 'title' | 'instructions' | 'status' | 'pass_mark' | 'max_attempts' | 'max_points' | 'due_at'>>) {
  mustAffect(check(await supabase.from('assessments').update(patch).eq('id', id).select('id')))
}
export async function deleteAssessment(id: string) {
  mustAffect(check(await supabase.from('assessments').delete().eq('id', id).select('id')))
}

// ---- quiz content ----
export async function loadQuiz(assessmentId: string): Promise<{ questions: Question[]; options: Option[] }> {
  const [q, o] = await Promise.all([
    supabase.from('quiz_questions').select('id, assessment_id, position, prompt, points').eq('assessment_id', assessmentId).order('position'),
    supabase.from('quiz_options').select('id, question_id, position, label').eq('assessment_id', assessmentId).order('position'),
  ])
  return { questions: check(q) as Question[], options: check(o) as Option[] }
}
/** Editors only. Learners get an empty result because the database never shows them the key. */
export async function loadKeys(assessmentId: string): Promise<Record<string, string>> {
  const rows = check(await supabase.from('quiz_answer_keys').select('question_id, option_id').eq('assessment_id', assessmentId)) as { question_id: string; option_id: string }[]
  return Object.fromEntries(rows.map(r => [r.question_id, r.option_id]))
}
export async function addQuestion(orgId: string, courseId: string, assessmentId: string, prompt: string, siblings: Question[]): Promise<string> {
  const row = check(await supabase.from('quiz_questions').insert({ org_id: orgId, course_id: courseId, assessment_id: assessmentId, prompt: prompt.trim(), position: nextPos(siblings) }).select('id').single())
  return (row as { id: string }).id
}
export async function updateQuestion(id: string, patch: { prompt?: string; points?: number }) {
  mustAffect(check(await supabase.from('quiz_questions').update(patch).eq('id', id).select('id')))
}
export async function deleteQuestion(id: string) {
  mustAffect(check(await supabase.from('quiz_questions').delete().eq('id', id).select('id')))
}
export async function addOption(orgId: string, courseId: string, assessmentId: string, questionId: string, label: string, siblings: Option[]) {
  check(await supabase.from('quiz_options').insert({ org_id: orgId, course_id: courseId, assessment_id: assessmentId, question_id: questionId, label: label.trim(), position: nextPos(siblings) }))
}
export async function updateOption(id: string, label: string) {
  mustAffect(check(await supabase.from('quiz_options').update({ label: label.trim() }).eq('id', id).select('id')))
}
export async function deleteOption(id: string) {
  mustAffect(check(await supabase.from('quiz_options').delete().eq('id', id).select('id')))
}
export async function setKey(orgId: string, courseId: string, assessmentId: string, questionId: string, optionId: string) {
  const res = await supabase.from('quiz_answer_keys').insert({ org_id: orgId, course_id: courseId, assessment_id: assessmentId, question_id: questionId, option_id: optionId })
  if (res.error?.code === '23505') { // a key already exists for this question: change it
    mustAffect(check(await supabase.from('quiz_answer_keys').update({ option_id: optionId }).eq('question_id', questionId).select('question_id')))
    return
  }
  if (res.error) throw res.error
}

// ---- taking a quiz ----
export async function submitQuiz(assessmentId: string, answers: Record<string, string>): Promise<QuizResult> {
  const { data, error } = await supabase.rpc('submit_quiz', { p_assessment: assessmentId, p_answers: answers })
  if (error) throw error
  return data as QuizResult
}
export async function myAttempts(assessmentId: string, userId: string): Promise<Attempt[]> {
  return check(await supabase.from('quiz_attempts').select('id, assessment_id, user_id, attempt_no, score_percent, passed, submitted_at').eq('assessment_id', assessmentId).eq('user_id', userId).order('attempt_no')) as Attempt[]
}

// ---- assignments ----
export async function mySubmission(assessmentId: string, userId: string): Promise<Submission | null> {
  return check(await supabase.from('assignment_submissions').select('id, assessment_id, user_id, body, status, points, feedback, submitted_at, graded_at').eq('assessment_id', assessmentId).eq('user_id', userId).maybeSingle()) as Submission | null
}
export async function saveSubmission(orgId: string, courseId: string, assessmentId: string, body: string, existing: Submission | null) {
  if (existing) {
    mustAffect(check(await supabase.from('assignment_submissions').update({ body: body.trim() }).eq('id', existing.id).select('id')))
  } else {
    check(await supabase.from('assignment_submissions').insert({ org_id: orgId, course_id: courseId, assessment_id: assessmentId, body: body.trim() }))
  }
}
export async function gradeSubmission(id: string, points: number, feedback: string) {
  const { error } = await supabase.rpc('grade_submission', { p_submission: id, p_points: points, p_feedback: feedback })
  if (error) throw error
}

// ---- review (course editors) ----
async function namesFor(ids: string[]): Promise<Map<string, string>> {
  if (!ids.length) return new Map()
  const rows = check(await supabase.from('profiles').select('id, full_name').in('id', [...new Set(ids)])) as { id: string; full_name: string | null }[]
  return new Map(rows.map(r => [r.id, r.full_name || 'Learner']))
}
export async function attemptsForReview(assessmentId: string) {
  const rows = check(await supabase.from('quiz_attempts').select('id, assessment_id, user_id, attempt_no, score_percent, passed, submitted_at').eq('assessment_id', assessmentId).order('submitted_at', { ascending: false })) as Attempt[]
  const names = await namesFor(rows.map(r => r.user_id))
  return rows.map(r => ({ ...r, name: names.get(r.user_id) ?? 'Learner' }))
}
export async function submissionsForReview(assessmentId: string) {
  const rows = check(await supabase.from('assignment_submissions').select('id, assessment_id, user_id, body, status, points, feedback, submitted_at, graded_at').eq('assessment_id', assessmentId).order('submitted_at', { ascending: false })) as Submission[]
  const names = await namesFor(rows.map(r => r.user_id))
  return rows.map(r => ({ ...r, name: names.get(r.user_id) ?? 'Learner' }))
}

// ---- learner overview for a whole course ----
export async function myCourseStatus(courseId: string, userId: string) {
  const [a, s] = await Promise.all([
    supabase.from('quiz_attempts').select('assessment_id, score_percent, passed').eq('course_id', courseId).eq('user_id', userId),
    supabase.from('assignment_submissions').select('assessment_id, status, points').eq('course_id', courseId).eq('user_id', userId),
  ])
  const best = new Map<string, { score: number; passed: boolean; attempts: number }>()
  for (const r of check(a) as { assessment_id: string; score_percent: number; passed: boolean }[]) {
    const cur = best.get(r.assessment_id)
    best.set(r.assessment_id, { score: Math.max(cur?.score ?? 0, r.score_percent), passed: (cur?.passed ?? false) || r.passed, attempts: (cur?.attempts ?? 0) + 1 })
  }
  const subs = new Map((check(s) as { assessment_id: string; status: string; points: number | null }[]).map(r => [r.assessment_id, r]))
  return { best, subs }
}
