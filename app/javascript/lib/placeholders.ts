/**
 * Placeholder constants for prompt editors
 * Used by PlaceholderPicker component for "/" command autocomplete
 */

export interface Placeholder {
  name: string
  value: string
}

export interface PlaceholderGroup {
  label: string
  placeholders: Placeholder[]
}

const SYSTEM_PROMPT_CATEGORIES = new Set([
  'product_discovery',
  'playbook_generation',
  'playbook_edit',
  'disc_inference',
  'reply_classification',
  'buying_signals',
])

const SYSTEM_PROMPT_SLUG_PATTERN = /_system(?:_[a-z]{2})?$/

function createPlaceholders(...names: string[]): Placeholder[] {
  return names.map((name) => ({ name, value: `{{${name}}}` }))
}

function flattenPlaceholderGroups(groups: PlaceholderGroup[]): Placeholder[] {
  return groups.flatMap((group) => group.placeholders)
}

function uniquePlaceholders(placeholders: Placeholder[]): Placeholder[] {
  return Array.from(new Map(placeholders.map((placeholder) => [placeholder.value, placeholder])).values())
}

export const SUBJECT_PLACEHOLDER_GROUPS: PlaceholderGroup[] = [
  { label: 'Lead', placeholders: createPlaceholders('first_name', 'last_name', 'full_name', 'company', 'job_title', 'company_domain') },
  { label: 'Sender', placeholders: createPlaceholders('sender_first_name', 'sender_last_name', 'sender_full_name', 'sender_company') },
]

// Subject-only placeholders (simpler set for subject line editors)
export const SUBJECT_PLACEHOLDERS = flattenPlaceholderGroups(SUBJECT_PLACEHOLDER_GROUPS)

export const BODY_PLACEHOLDER_GROUPS: PlaceholderGroup[] = [
  {
    label: 'Lead',
    placeholders: createPlaceholders(
      'first_name',
      'last_name',
      'full_name',
      'company',
      'company_domain',
      'company_website',
      'job_title',
      'email',
      'linkedin_url',
      'location',
    ),
  },
  {
    label: 'Enrichment',
    placeholders: createPlaceholders(
      'lead.disc_profile',
      'lead.linkedin_headline',
      'lead.linkedin_summary',
      'lead.linkedin_scraped',
      'lead.linkedin_posts',
      'lead.company_website_scraped',
      'lead.buying_signals',
    ),
  },
  {
    label: 'Sender',
    placeholders: createPlaceholders('sender_first_name', 'sender_last_name', 'sender_full_name', 'sender_company'),
  },
  {
    label: 'Organization',
    placeholders: createPlaceholders('organization.website_url', 'organization.description'),
  },
  {
    label: 'Playbook',
    placeholders: createPlaceholders(
      'playbook.value_proposition',
      'playbook.full_context',
      'playbook.product.name',
      'playbook.product.description',
      'playbook.icps',
      'playbook.use_cases',
      'playbook.references',
      'playbook.proof_points',
      'playbook.knowledge_base',
    ),
  },
  {
    label: 'Persona',
    placeholders: createPlaceholders('persona.name', 'persona.title', 'persona.pain_points'),
  },
  {
    label: 'Other',
    placeholders: createPlaceholders('previous_email_body', 'calendly_link', 'locale'),
  },
]

// Full set of placeholders for body/content editors
export const BODY_PLACEHOLDERS = flattenPlaceholderGroups(BODY_PLACEHOLDER_GROUPS)

export const PRODUCT_DISCOVERY_PLACEHOLDER_GROUPS: PlaceholderGroup[] = [
  {
    label: 'Discovery Input',
    placeholders: createPlaceholders('website_url', 'scraped_content'),
  },
]

export const PLAYBOOK_GENERATION_PLACEHOLDER_GROUPS: PlaceholderGroup[] = [
  {
    label: 'Website',
    placeholders: createPlaceholders('website_url', 'scraped_content'),
  },
  {
    label: 'Generation',
    placeholders: createPlaceholders('product_name', 'target_language', 'language_instruction'),
  },
]

export const PLAYBOOK_EDIT_PLACEHOLDER_GROUPS: PlaceholderGroup[] = [
  {
    label: 'Instruction',
    placeholders: createPlaceholders('instruction', 'target_language', 'language_instruction'),
  },
  {
    label: 'Product',
    placeholders: createPlaceholders('product_name', 'product_description'),
  },
  {
    label: 'Current Playbook',
    placeholders: createPlaceholders(
      'current_value_proposition',
      'current_personae',
      'current_use_cases',
      'current_references',
      'current_proof_points',
    ),
  },
  {
    label: 'Files',
    placeholders: createPlaceholders('file_contents'),
  },
]

export const DISC_INFERENCE_PLACEHOLDER_GROUPS: PlaceholderGroup[] = [
  {
    label: 'Profile',
    placeholders: createPlaceholders('display_name', 'job_title_line', 'company_line', 'location_line'),
  },
  {
    label: 'LinkedIn',
    placeholders: createPlaceholders(
      'linkedin_headline_section',
      'linkedin_summary_section',
      'experience_section',
      'skills_section',
      'posts_section',
    ),
  },
]

export const REPLY_CLASSIFICATION_PLACEHOLDER_GROUPS: PlaceholderGroup[] = [
  {
    label: 'Reply',
    placeholders: createPlaceholders('subject', 'body_plain', 'body_html'),
  },
]

export const REPLY_GENERATION_PLACEHOLDER_GROUPS: PlaceholderGroup[] = [
  {
    label: 'Conversation',
    placeholders: createPlaceholders('conversation_thread', 'latest_incoming_message'),
  },
  {
    label: 'Context',
    placeholders: createPlaceholders('lead_name', 'lead_email', 'mailbox_email'),
  },
]

export const BUYING_SIGNALS_PLACEHOLDER_GROUPS: PlaceholderGroup[] = [
  {
    label: 'Buying Signals',
    placeholders: createPlaceholders(
      'current_date',
      'company_name',
      'company_domain',
      'company_website_url',
      'company_website_summary',
      'playbook_context',
      'lookback_days',
    ),
  },
]

export const PROMPT_CATEGORY_PLACEHOLDER_GROUPS: Record<string, PlaceholderGroup[]> = {
  product_discovery: PRODUCT_DISCOVERY_PLACEHOLDER_GROUPS,
  playbook_generation: PLAYBOOK_GENERATION_PLACEHOLDER_GROUPS,
  playbook_edit: PLAYBOOK_EDIT_PLACEHOLDER_GROUPS,
  subject_prompt: SUBJECT_PLACEHOLDER_GROUPS,
  body_prompt: BODY_PLACEHOLDER_GROUPS,
  disc_inference: DISC_INFERENCE_PLACEHOLDER_GROUPS,
  reply_classification: REPLY_CLASSIFICATION_PLACEHOLDER_GROUPS,
  reply_generation: REPLY_GENERATION_PLACEHOLDER_GROUPS,
  buying_signals: BUYING_SIGNALS_PLACEHOLDER_GROUPS,
}

function isSystemPrompt(category?: string | null, slug?: string | null): boolean {
  if (!category || !slug) return false
  if (!SYSTEM_PROMPT_CATEGORIES.has(category)) return false

  return SYSTEM_PROMPT_SLUG_PATTERN.test(slug)
}

export function getPlaceholderGroupsForPromptCategory(category?: string | null, slug?: string | null): PlaceholderGroup[] {
  if (!category) return []
  if (isSystemPrompt(category, slug)) return []

  return PROMPT_CATEGORY_PLACEHOLDER_GROUPS[category] || []
}

export function getPlaceholdersForPromptCategory(category?: string | null, slug?: string | null): Placeholder[] {
  return flattenPlaceholderGroups(getPlaceholderGroupsForPromptCategory(category, slug))
}

// Alias for convenience - "all placeholders"
export const ALL_PLACEHOLDERS = uniquePlaceholders(
  Object.values(PROMPT_CATEGORY_PLACEHOLDER_GROUPS).flatMap(flattenPlaceholderGroups),
)
