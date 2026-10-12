import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { supabase } from '@/lib/supabase'
import type { Workspace, PermissionKey } from '@/types/domain'

const ACTIVE_KEY = 'tv-active-workspace'

/**
 * Two separate things live here and must stay separate:
 *  - `official`   the user's membership of the official Tech Village LMS (learner experience)
 *  - `workspaces` customer workspaces the user belongs to (administration experience)
 */
export const useWorkspaceStore = defineStore('workspace', () => {
  const memberships = ref<Workspace[]>([])
  const activeId = ref<string | null>(null)
  const permsByOrg = ref<Record<string, Set<string>>>({})
  const loading = ref(false)
  const loaded = ref(false)

  const official = computed(() => memberships.value.find(m => m.is_platform_tenant) ?? null)
  const workspaces = computed(() => memberships.value.filter(m => !m.is_platform_tenant))
  const active = computed(() => workspaces.value.find(w => w.org_id === activeId.value) ?? null)
  const ownedWorkspace = computed(() => workspaces.value.find(w => w.role_key === 'owner') ?? null)

  /**
   * UI convenience only. Hiding a button is not security: Postgres RLS and the
   * SECURITY DEFINER functions re-check every action on the server.
   */
  function canIn(orgId: string | null | undefined, permission: PermissionKey) {
    return !!orgId && !!permsByOrg.value[orgId]?.has(permission)
  }
  function can(permission: PermissionKey) {
    return canIn(activeId.value, permission)
  }

  async function loadPermissionsFor(orgId: string | null | undefined) {
    if (!orgId) return
    const { data } = await supabase.rpc('my_permissions', { p_org: orgId })
    permsByOrg.value = { ...permsByOrg.value, [orgId]: new Set((data as string[] | null) ?? []) }
  }

  async function load() {
    loading.value = true
    try {
      const { data, error } = await supabase.rpc('my_workspaces')
      if (error) throw error
      memberships.value = (data as Workspace[] | null) ?? []

      // Only trust a stored id if the server still lists it for this user.
      const stored = localStorage.getItem(ACTIVE_KEY)
      const valid = workspaces.value.find(w => w.org_id === stored)
      activeId.value = valid?.org_id ?? ownedWorkspace.value?.org_id ?? workspaces.value[0]?.org_id ?? null
      permsByOrg.value = {}
      await Promise.all([loadPermissionsFor(activeId.value), loadPermissionsFor(official.value?.org_id)])
      loaded.value = true
    } finally {
      loading.value = false
    }
  }

  async function switchTo(orgId: string) {
    if (!workspaces.value.some(w => w.org_id === orgId)) return
    activeId.value = orgId
    try { localStorage.setItem(ACTIVE_KEY, orgId) } catch { /* storage may be unavailable */ }
    await loadPermissionsFor(orgId)
  }

  function reset() {
    memberships.value = []
    activeId.value = null
    permsByOrg.value = {}
    loaded.value = false
  }

  return { memberships, official, workspaces, active, ownedWorkspace, activeId, permsByOrg, loading, loaded, can, canIn, load, switchTo, reset }
})
