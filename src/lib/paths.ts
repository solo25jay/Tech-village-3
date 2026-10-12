/** The same course screens serve the official LMS (/learn) and customer workspaces (/app). */
export type Scope = 'workspace' | 'official'
const base = (scope: Scope) => (scope === 'official' ? '/learn/courses' : '/app/courses')
export const coursesPath = (scope: Scope) => base(scope)
export const coursePath = (scope: Scope, id: string) => `${base(scope)}/${id}`
export const courseEditPath = (scope: Scope, id: string) => `${base(scope)}/${id}/edit`
