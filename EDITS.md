# Phase 6: edits to four EXISTING files

Everything else in this folder is a NEW file: copy it to the same path in your project.
These four existing files need only small additions. Nothing is removed.

---------------------------------------------------------------------------
## 1. src/lib/paths.ts  (add at the very END of the file)

```ts

// ---- assessments ----
export const assessmentPath = (scope: Scope, courseId: string, id: string) => `${base(scope)}/${courseId}/assessments/${id}`
export const assessmentEditPath = (scope: Scope, courseId: string, id: string) => `${assessmentPath(scope, courseId, id)}/edit`
export const assessmentReviewPath = (scope: Scope, courseId: string, id: string) => `${assessmentPath(scope, courseId, id)}/review`
```

---------------------------------------------------------------------------
## 2. src/components/CourseEditor.vue   (two additions)

(a) In the <script setup> imports, directly AFTER this line:
```ts
import LessonContent from '@/components/LessonContent.vue'
```
add:
```ts
import CourseAssessments from '@/components/CourseAssessments.vue'
```

(b) Near the END of the file you will find:
```html
        </section>
      </div>
    </template>
  </div>
</template>
```
Insert the new <div> between the `      </div>` and `    </template>` lines, so it reads:
```html
        </section>
      </div>

      <div class="mt-10"><CourseAssessments :org-id="orgId" :course-id="courseId" :scope="scope" mode="editor" /></div>
    </template>
  </div>
</template>
```

---------------------------------------------------------------------------
## 3. src/components/CourseViewer.vue   (two additions)

(a) In the imports, directly AFTER:
```ts
import LessonContent from '@/components/LessonContent.vue'
```
add:
```ts
import CourseAssessments from '@/components/CourseAssessments.vue'
```

(b) Near the END of the file you will find:
```html
        </article>
      </div>
    </template>
  </div>
</template>
```
Make it read:
```html
        </article>
      </div>

      <div v-if="canSeeContent" class="mt-10"><CourseAssessments :org-id="orgId" :course-id="courseId" :scope="scope" mode="learner" /></div>
    </template>
  </div>
</template>
```

---------------------------------------------------------------------------
## 4. src/router/index.ts   (two blocks)

(a) In the **/learn** children, directly AFTER the line whose name is `learn-course-edit`, add:
```ts
        { path: 'courses/:courseId/assessments/:assessmentId', name: 'learn-assessment', component: () => import('@/pages/AssessmentPage.vue'), props: { scope: 'official' }, meta: { needsLearner: true, title: 'Assessment' } },
        { path: 'courses/:courseId/assessments/:assessmentId/edit', name: 'learn-assessment-edit', component: () => import('@/pages/AssessmentEditPage.vue'), props: { scope: 'official' }, meta: { needsLearner: true, title: 'Edit assessment' } },
        { path: 'courses/:courseId/assessments/:assessmentId/review', name: 'learn-assessment-review', component: () => import('@/pages/AssessmentReviewPage.vue'), props: { scope: 'official' }, meta: { needsLearner: true, title: 'Assessment results' } },
```

(b) In the **/app** children, directly AFTER the line whose name is `course-edit`, add:
```ts
        { path: 'courses/:courseId/assessments/:assessmentId', name: 'assessment', component: () => import('@/pages/AssessmentPage.vue'), props: { scope: 'workspace' }, meta: { title: 'Assessment' } },
        { path: 'courses/:courseId/assessments/:assessmentId/edit', name: 'assessment-edit', component: () => import('@/pages/AssessmentEditPage.vue'), props: { scope: 'workspace' }, meta: { title: 'Edit assessment' } },
        { path: 'courses/:courseId/assessments/:assessmentId/review', name: 'assessment-review', component: () => import('@/pages/AssessmentReviewPage.vue'), props: { scope: 'workspace' }, meta: { title: 'Assessment results' } },
```
