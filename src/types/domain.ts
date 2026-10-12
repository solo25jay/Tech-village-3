export type OrgType =
  | 'school' | 'university_college' | 'training_academy' | 'coding_bootcamp'
  | 'private_tutoring' | 'independent_instructor' | 'corporate_training' | 'other'

export const ORG_TYPE_LABELS: Record<OrgType, string> = {
  school: 'School',
  university_college: 'University or college',
  training_academy: 'Training academy',
  coding_bootcamp: 'Coding bootcamp',
  private_tutoring: 'Private tutoring business',
  independent_instructor: 'Independent instructor',
  corporate_training: 'Corporate training',
  other: 'Other',
}

export type SignupIntent = 'learner' | 'workspace' | 'invited'

/** A membership of the signed-in user: either the official Tech Village LMS or a customer workspace. */
export interface Workspace {
  org_id: string
  name: string
  workspace_name: string
  slug: string
  org_type: OrgType
  status: 'active' | 'suspended'
  is_platform_tenant: boolean
  logo_url: string | null
  role_key: string
  role_name: string
}

export interface OrganisationDetails {
  id: string
  name: string
  workspace_name: string
  slug: string
  org_type: OrgType
  description: string | null
  country: string | null
  contact_email: string | null
  contact_phone: string | null
  website: string | null
  logo_url: string | null
}

export interface Profile {
  id: string
  full_name: string | null
  avatar_url: string | null
  country: string | null
  signup_intent: SignupIntent | null
}

export type PermissionKey =
  | 'org.manage' | 'org.branding' | 'members.manage' | 'roles.manage'
  | 'courses.view' | 'courses.create' | 'courses.manage' | 'enrolments.manage'
  | 'billing.manage' | 'reports.view' | 'audit.view'
