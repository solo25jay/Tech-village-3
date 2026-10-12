import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useWorkspaceStore } from '@/stores/workspace'

declare module 'vue-router' {
  interface RouteMeta {
    requiresAuth?: boolean
    guestOnly?: boolean
    needsWorkspace?: boolean   // must belong to a customer workspace
    needsLearner?: boolean     // must have joined the official Tech Village LMS
    platformAdmin?: boolean
    title?: string
    description?: string
  }
}

const router = createRouter({
  history: createWebHistory(),
  scrollBehavior: () => ({ top: 0 }),
  routes: [
    // ---- Public website and the two registration journeys ----
    {
      path: '/',
      component: () => import('@/layouts/PublicLayout.vue'),
      children: [
        { path: '', name: 'home', component: () => import('@/pages/HomePage.vue'),
          meta: { title: 'Tech Village: learn, build, earn', description: 'Join Tech Village to learn technology skills, build real projects and earn from them. Or create your own branded learning platform for your school, academy or company.' } },
        { path: 'about', name: 'about', component: () => import('@/pages/AboutPage.vue'),
          meta: { title: 'About', description: 'Tech Village combines teaching, practice, mentorship and community, and lets anyone run their own learning platform.' } },
        { path: 'programmes', name: 'programmes', component: () => import('@/pages/ProgrammesPage.vue'),
          meta: { title: 'Learning paths', description: 'Explore Tech Village learning paths in web development, data and AI, mobile, cybersecurity, design and career skills.' } },
        { path: 'pricing', name: 'pricing', component: () => import('@/pages/PricingPage.vue'),
          meta: { title: 'Pricing', description: 'Plans for individual tutors, academies, schools and companies who want to run their own learning platform.' } },
        { path: 'contact', name: 'contact', component: () => import('@/pages/ContactPage.vue'),
          meta: { title: 'Contact', description: 'Ask a question, register interest in a programme, or talk to us about running your own learning platform.' } },
        { path: 'login', name: 'login', component: () => import('@/pages/LoginPage.vue'), meta: { guestOnly: true, title: 'Sign in' } },
        { path: 'signup', name: 'signup', component: () => import('@/pages/SignupChoicePage.vue'),
          meta: { guestOnly: true, title: 'Sign up', description: 'Join Tech Village as a learner, or create your own LMS workspace for your school, academy or business.' } },
        { path: 'signup/learner', name: 'signup-learner', component: () => import('@/pages/LearnerSignupPage.vue'), meta: { guestOnly: true, title: 'Join Tech Village' } },
        { path: 'signup/lms', name: 'signup-lms', component: () => import('@/pages/LmsSignupPage.vue'), meta: { title: 'Create your own LMS' } },
        { path: 'signup/invited', name: 'signup-invited', component: () => import('@/pages/InvitedSignupPage.vue'), meta: { guestOnly: true, title: 'Create your account' } },
        { path: 'invite/:token', name: 'invite', component: () => import('@/pages/InvitePage.vue'), meta: { title: 'Invitation' } },
        { path: 'register', redirect: { name: 'signup' } },   // old links keep working
        { path: 'reset-password', name: 'reset-password', component: () => import('@/pages/ResetPasswordPage.vue'), meta: { title: 'Reset password' } },
      ],
    },
    // ---- Signed-in router: sends people to the right place ----
    { path: '/hub', name: 'hub', component: () => import('@/pages/HubPage.vue'), meta: { requiresAuth: true } },

    // ---- Official Tech Village LMS (learner experience) ----
    {
      path: '/learn',
      component: () => import('@/layouts/LearnerLayout.vue'),
      meta: { requiresAuth: true },
      children: [
        { path: '', redirect: { name: 'learn-dashboard' } },
        { path: 'join', name: 'join', component: () => import('@/pages/JoinTechVillagePage.vue') },
        { path: 'dashboard', name: 'learn-dashboard', component: () => import('@/pages/LearnerDashboardPage.vue'), meta: { needsLearner: true } },
        { path: 'courses', name: 'learn-courses', component: () => import('@/pages/CoursesPage.vue'), props: { scope: 'official' }, meta: { needsLearner: true, title: 'Courses' } },
        { path: 'courses/:courseId', name: 'learn-course', component: () => import('@/pages/CoursePage.vue'), props: { scope: 'official' }, meta: { needsLearner: true, title: 'Course' } },
        { path: 'courses/:courseId/edit', name: 'learn-course-edit', component: () => import('@/pages/CourseEditPage.vue'), props: { scope: 'official' }, meta: { needsLearner: true, title: 'Edit course' } },
      ],
    },

    // ---- Customer workspace administration ----
    {
      path: '/app',
      component: () => import('@/layouts/WorkspaceLayout.vue'),
      meta: { requiresAuth: true, needsWorkspace: true },
      children: [
        { path: '', redirect: { name: 'dashboard' } },
        { path: 'dashboard', name: 'dashboard', component: () => import('@/pages/DashboardPage.vue') },
        { path: 'settings', name: 'settings', component: () => import('@/pages/OrgSettingsPage.vue') },
        { path: 'courses', name: 'courses', component: () => import('@/pages/CoursesPage.vue'), props: { scope: 'workspace' }, meta: { title: 'Courses' } },
        { path: 'courses/:courseId', name: 'course', component: () => import('@/pages/CoursePage.vue'), props: { scope: 'workspace' }, meta: { title: 'Course' } },
        { path: 'courses/:courseId/edit', name: 'course-edit', component: () => import('@/pages/CourseEditPage.vue'), props: { scope: 'workspace' }, meta: { title: 'Edit course' } },
        { path: 'team', name: 'team', component: () => import('@/pages/TeamPage.vue'), meta: { title: 'Team' } },
      ],
    },

    // ---- Tech Village platform administration ----
    {
      path: '/admin',
      component: () => import('@/layouts/AdminLayout.vue'),
      meta: { requiresAuth: true, platformAdmin: true },
      children: [
        { path: '', name: 'admin', component: () => import('@/pages/AdminWorkspacesPage.vue') },
      ],
    },

    { path: '/:pathMatch(.*)*', name: 'not-found', component: () => import('@/pages/NotFoundPage.vue') },
  ],
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()
  await auth.init()

  if (to.meta.requiresAuth && !auth.isAuthenticated) {
    return { name: 'login', query: { next: to.fullPath } }
  }
  if (to.meta.guestOnly && auth.isAuthenticated) return { name: 'hub' }

  if (auth.isAuthenticated) {
    const ws = useWorkspaceStore()
    if (!ws.loaded && !ws.loading) {
      try { await ws.load() } catch { /* the hub shows a retry state */ }
    }
    if (to.meta.platformAdmin && !auth.isPlatformAdmin) return { name: 'hub' }
    if (to.meta.needsWorkspace && !ws.workspaces.length) return { name: 'hub' }
    if (to.meta.needsLearner && !ws.official) return { name: 'join' }
  }
})

router.afterEach((to) => {
  const base = 'Tech Village'
  document.title = to.meta.title && to.name !== 'home' ? `${to.meta.title} | ${base}` : (to.meta.title ?? base)
  const desc = to.meta.description
  const tag = document.querySelector<HTMLMetaElement>('meta[name="description"]')
  if (desc && tag) tag.content = desc
})

export default router
