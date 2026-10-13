/** The same course screens serve the official LMS (/learn) and customer workspaces (/app). */
export type Scope = 'workspace' | 'official'
const base = (scope: Scope) => (scope === 'official' ? '/learn/courses' : '/app/courses')
export const coursesPath = (scope: Scope) => base(scope)
export const coursePath = (scope: Scope, id: string) => `${base(scope)}/${id}`
export const courseEditPath = (scope: Scope, id: string) => `${base(scope)}/${id}/edit`
export const assessmentPath = (scope: Scope, courseId: string, id: string) => `${base(scope)}/${courseId}/assessments/${id}`
export const assessmentEditPath = (scope: Scope, courseId: string, id: string) => `${assessmentPath(scope, courseId, id)}/edit`
export const assessmentReviewPath = (scope: Scope, courseId: string, id: string) => `${assessmentPath(scope, courseId, id)}/review`