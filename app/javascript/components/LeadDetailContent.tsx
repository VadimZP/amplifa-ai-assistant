import React, { useState } from 'react'
import { Link } from '@inertiajs/react'
import { t } from '../lib/i18n'
import { 
  User, Building2, Mail, Linkedin, MapPin, Globe,
  MessageSquare, Clock, ChevronDown,
  ChevronUp, ExternalLink, AlertCircle,
  Briefcase
} from 'lucide-react'
import { Badge } from './ui/Badge'
import ThreadMessage from './ThreadMessage'
interface LinkedInExperience {
  title: string | null
  company: string | null
  description: string | null
  start_date: string | null
  end_date: string | null
  is_current: boolean
}

interface LinkedInEducation {
  school: string | null
  degree: string | null
  field_of_study: string | null
  start_date: string | null
  end_date: string | null
}

export interface LeadDetailData {
  id: number
  email: string
  first_name: string | null
  last_name: string | null
  full_name: string | null
  display_name: string
  company: string | null
  company_website: string | null
  job_title: string | null
  location: string | null
  linkedin_url: string | null
  linkedin_profile_photo_url: string | null
  blacklisted: boolean
  blacklist_reason: string | null
  custom_fields: Record<string, unknown> | null
  person?: { id: number; display_name: string | null } | null
  email_provider: string | null
  preferred_locale: string | null
  locale_source: string | null
  
  timezone: string | null
  timezone_resolved_at: string | null
  disc_profile: string | null
  disc_profile_data: { confidence?: number; reasoning?: string } | null
  disc_profile_assessed_at: string | null
  disc_profile_source: string | null
  linkedin_scraped_at: string | null
  linkedin_headline: string | null
  linkedin_summary: string | null
  linkedin_scraped_data: {
    experience?: LinkedInExperience[]
    education?: LinkedInEducation[]
  } | null
  linkedin_posts: Array<{ text: string; url: string; date: string }> | null
  linkedin_posts_scraped_at: string | null
  company_website_scraped_at: string | null
  company_website_content: string | null
  company_website_summary: string | null
  buying_signals_summary_status: string | null
  buying_signals_markdown: string
  buying_signals_highlights?: string[]
  buying_signals_relevance_rating?: number | null
  buying_signals_generated_at: string | null
  
  agent_leads: Array<{
    id: number
    agent: {
      id: number
      name: string
      status: string
      sequence_steps: Array<{
        id: number
        position: number
        display_name: string
        delay_days: number
      }>
    }
    status: string
    delivery_status: string
    sequence_position: number
    assigned_mailbox: { id: number; email: string; provider_type: string | null } | null
    generated_messages: Array<{
      id: number
      sequence_step_id: number
      subject: string
      body: string
      status: string
      manually_edited: boolean
      sent_at: string | null
    }>
  }>

  conversations?: Array<{
    id: number
    status: string
    mailbox: { id: number; email: string }
    thread: Array<{
      id: number
      type: 'incoming' | 'outgoing'
      source?: string
      from: string
      subject: string | null
      body_plain: string | null
      body_html: string | null
      message_at: string
      is_bounce: boolean
      is_out_of_office: boolean
    }>
  }>
  
  created_at: string
  updated_at: string
}

interface SectionState {
  basic_info: boolean
  messages: boolean
}

interface LeadDetailContentProps {
  data: LeadDetailData
  onEnrichment?: (type: string) => Promise<void>
  onGenerateMessages?: (agentLeadId: number) => Promise<void>
  enrichingType?: string | null
  generatingFor?: number | null
  actionError?: string | null
  variant?: 'slideover' | 'page'
  showMessages?: boolean
  hideIncompleteBuyingSignals?: boolean
}

const CollapsibleHeader = ({ 
  title, 
  subtitle,
  expanded, 
  onToggle, 
  icon: Icon,
  action
}: { 
  title: string, 
  subtitle?: string,
  expanded: boolean, 
  onToggle: () => void,
  icon?: React.ElementType,
  action?: React.ReactNode
}) => (
  <button 
    onClick={onToggle}
    className="flex items-center justify-between w-full py-2 group focus:outline-none"
  >
    <div className="flex items-center gap-2">
      {Icon && <Icon className="size-4 text-[var(--foreground-muted)] group-hover:text-[var(--foreground)] transition-colors" />}
      <h3 className="text-sm font-medium text-[var(--foreground-muted)] group-hover:text-[var(--foreground)] transition-colors">
        {title}
      </h3>
      {subtitle && (
        <span className="text-xs text-[var(--foreground-subtle)]">· {subtitle}</span>
      )}
    </div>
    <div className="flex items-center gap-2">
      {action}
      {expanded ? (
        <ChevronUp className="size-4 text-[var(--foreground-subtle)]" />
      ) : (
        <ChevronDown className="size-4 text-[var(--foreground-subtle)]" />
      )}
    </div>
  </button>
)

export default function LeadDetailContent({
  data,
  actionError,
  variant = 'page',
  showMessages = true
}: LeadDetailContentProps) {
  const [sections, setSections] = useState<SectionState>({
    basic_info: true,
    messages: showMessages
  })

  const toggleSection = (section: keyof SectionState) => {
    setSections(prev => ({ ...prev, [section]: !prev[section] }))
  }

  const conversations = data.conversations || []
  const hasConversations = conversations.length > 0

  return (
    <div className="space-y-6">
      {actionError && (
        <div className="p-3 bg-red-900/50 border border-red-500/50 rounded-lg flex items-center gap-2 text-red-200 text-sm animate-in fade-in slide-in-from-top-2">
          <AlertCircle className="size-4 shrink-0" />
          {actionError}
        </div>
      )}

      <div className="space-y-2">
        <CollapsibleHeader 
          title={t('admin.leads.modal.sections.basic_info', { defaultValue: 'Basic Info' })}
          expanded={sections.basic_info}
          onToggle={() => toggleSection('basic_info')}
          icon={User}
        />
        
        {sections.basic_info && (
          <div className="grid grid-cols-1 gap-3 pl-6 border-l border-[var(--border)] ml-2">
            {data.linkedin_profile_photo_url && (
              <div className="flex items-start gap-3 text-sm">
                <User className="size-4 text-[var(--foreground-subtle)] mt-0.5 shrink-0" />
                <div className="flex flex-col">
                  <span className="text-[var(--foreground-subtle)] text-xs">
                    {t('admin.leads.modal.fields.linkedin_photo', { defaultValue: 'LinkedIn Photo' })}
                  </span>
                  <img
                    src={data.linkedin_profile_photo_url}
                    alt={data.display_name}
                    className="mt-1 h-12 w-12 rounded-full object-cover border border-[var(--border)]"
                    loading="lazy"
                  />
                </div>
              </div>
            )}
            <div className="flex items-start gap-3 text-sm">
              <Mail className="size-4 text-[var(--foreground-subtle)] mt-0.5 shrink-0" />
              <div className="flex flex-col">
                <span className="text-[var(--foreground-subtle)] text-xs">{t('admin.leads.modal.fields.email', { defaultValue: 'Email' })}</span>
                <div className="flex items-center gap-2">
                  <a href={`mailto:${data.email}`} className="text-[var(--foreground)] hover:underline truncate">{data.email}</a>
                  {data.email_provider ? (
                    <Badge
                      variant={data.email_provider === 'google' ? 'success' : 'info'}
                      size="sm"
                      className="h-5 px-1.5 text-[10px] rounded-full"
                    >
                      {data.email_provider === 'google' && <span className="w-1.5 h-1.5 rounded-full bg-current" />}
                      {data.email_provider === 'google' ? 'Google' : 'M365'}
                    </Badge>
                  ) : (
                    <Badge variant="draft" size="sm" className="h-5 px-1.5 text-[10px] rounded-full">
                      Unknown
                    </Badge>
                  )}
                </div>
              </div>
            </div>

            {data.job_title && (
              <div className="flex items-start gap-3 text-sm">
                <Briefcase className="size-4 text-[var(--foreground-subtle)] mt-0.5 shrink-0" />
                <div className="flex flex-col">
                  <span className="text-[var(--foreground-subtle)] text-xs">{t('admin.leads.modal.fields.job_title', { defaultValue: 'Job Title' })}</span>
                  <span className="text-[var(--foreground)]">{data.job_title}</span>
                </div>
              </div>
            )}

            {data.company && (
              <div className="flex items-start gap-3 text-sm">
                <Building2 className="size-4 text-[var(--foreground-subtle)] mt-0.5 shrink-0" />
                <div className="flex flex-col">
                  <span className="text-[var(--foreground-subtle)] text-xs">{t('admin.leads.modal.fields.company', { defaultValue: 'Company' })}</span>
                  <span className="text-[var(--foreground)]">{data.company}</span>
                </div>
              </div>
            )}

            {data.person?.id && (
              <div className="flex items-start gap-3 text-sm">
                <User className="size-4 text-[var(--foreground-subtle)] mt-0.5 shrink-0" />
                <div className="flex flex-col">
                  <span className="text-[var(--foreground-subtle)] text-xs">{t('admin.leads.modal.fields.person', { defaultValue: 'Person' })}</span>
                  <Link
                    href={`/admin/people/${data.person.id}`}
                    className="text-[var(--accent)] hover:text-[var(--accent-hover)] hover:underline"
                  >
                    {data.person.display_name || t('admin.leads.modal.fields.view_person', { defaultValue: 'View person record' })}
                  </Link>
                </div>
              </div>
            )}

            {data.location && (
              <div className="flex items-start gap-3 text-sm">
                <MapPin className="size-4 text-[var(--foreground-subtle)] mt-0.5 shrink-0" />
                <div className="flex flex-col">
                  <span className="text-[var(--foreground-subtle)] text-xs">{t('admin.leads.modal.fields.location', { defaultValue: 'Location' })}</span>
                  <span className="text-[var(--foreground)]">{data.location}</span>
                </div>
              </div>
            )}

            {data.timezone && (
              <div className="flex items-start gap-3 text-sm">
                <Clock className="size-4 text-[var(--foreground-subtle)] mt-0.5 shrink-0" />
                <div className="flex flex-col">
                  <span className="text-[var(--foreground-subtle)] text-xs">{t('admin.leads.modal.fields.timezone', { defaultValue: 'Timezone' })}</span>
                  <span className="text-[var(--foreground)]">{data.timezone}</span>
                </div>
              </div>
            )}

            {data.preferred_locale && (
              <div className="flex items-start gap-3 text-sm">
                <Globe className="size-4 text-[var(--foreground-subtle)] mt-0.5 shrink-0" />
                <div className="flex flex-col">
                  <span className="text-[var(--foreground-subtle)] text-xs">Locale</span>
                  <span className="text-[var(--foreground)]">{data.preferred_locale}</span>
                </div>
              </div>
            )}

            {data.linkedin_url && (
              <div className="flex items-start gap-3 text-sm">
                <Linkedin className="size-4 text-[var(--foreground-subtle)] mt-0.5 shrink-0" />
                <div className="flex flex-col">
                  <span className="text-[var(--foreground-subtle)] text-xs">{t('admin.leads.modal.fields.linkedin_url', { defaultValue: 'LinkedIn' })}</span>
                  <a 
                    href={data.linkedin_url} 
                    target="_blank" 
                    rel="noreferrer" 
                    className="text-[var(--accent)] hover:text-[var(--accent-hover)] hover:underline flex items-center gap-1"
                  >
                    {t('admin.leads.modal.fields.view_profile', { defaultValue: 'View Profile' })}
                    <ExternalLink className="size-3" />
                  </a>
                </div>
              </div>
            )}

            {data.company_website && (
              <div className="flex items-start gap-3 text-sm">
                <Globe className="size-4 text-[var(--foreground-subtle)] mt-0.5 shrink-0" />
                <div className="flex flex-col">
                  <span className="text-[var(--foreground-subtle)] text-xs">{t('admin.leads.modal.fields.website', { defaultValue: 'Website' })}</span>
                  <a 
                    href={data.company_website.startsWith('http') ? data.company_website : `https://${data.company_website}`}
                    target="_blank" 
                    rel="noreferrer" 
                    className="text-[var(--accent)] hover:text-[var(--accent-hover)] hover:underline flex items-center gap-1"
                  >
                    {data.company_website}
                    <ExternalLink className="size-3" />
                  </a>
                </div>
              </div>
            )}
          </div>
        )}
      </div>

      {showMessages && variant === 'page' && (
        <div className="space-y-2">
          <CollapsibleHeader 
            title={t('admin.leads.modal.sections.messages', { defaultValue: 'Messages' })}
            expanded={sections.messages}
            onToggle={() => toggleSection('messages')}
            icon={MessageSquare}
          />
          
          {sections.messages && (
            <div className="pl-6 border-l border-[var(--border)] ml-2 space-y-6">
              {hasConversations && (
                <div className="space-y-4">
                  <div className="flex items-center gap-2 text-xs uppercase tracking-wider text-[var(--foreground-subtle)]">
                    {t('admin.leads.modal.messages.threads', { defaultValue: 'Replies & Threads' })}
                  </div>
                  {conversations.map((conversation) => (
                    <div key={conversation.id} className="rounded-lg border border-[var(--border)] bg-[var(--card)] overflow-hidden">
                      <div className="flex items-center justify-between p-3 bg-[var(--card-hover)] border-b border-[var(--border)]">
                        <div className="text-sm font-medium text-[var(--foreground)]">
                          {conversation.mailbox.email}
                        </div>
                        <span className="text-xs text-[var(--foreground-subtle)] capitalize">{conversation.status}</span>
                      </div>
                      <div className="p-3">
                        {conversation.thread.length > 0 ? (
                          conversation.thread.map((message, index) => (
                            <ThreadMessage
                              key={`${message.source || 'thread'}-${message.id}`}
                              message={message}
                              previousMessage={index > 0 ? conversation.thread[index - 1] : undefined}
                            />
                          ))
                        ) : (
                          <p className="text-sm text-[var(--foreground-subtle)]">
                            {t('admin.leads.modal.messages.no_thread', { defaultValue: 'No messages in this thread yet.' })}
                          </p>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>
      )}

      {showMessages && variant === 'slideover' && (
        <div className="space-y-2">
          <CollapsibleHeader 
            title={t('admin.leads.modal.sections.messages', { defaultValue: 'Messages' })}
            expanded={sections.messages}
            onToggle={() => toggleSection('messages')}
            icon={MessageSquare}
          />
          
          {sections.messages && (
            <div className="pl-6 border-l border-[var(--border)] ml-2 space-y-6">
              <div className="space-y-4">
                <div className="flex items-center gap-2 text-xs uppercase tracking-wider text-[var(--foreground-subtle)]">
                  {t('admin.leads.modal.messages.conversations', { defaultValue: 'Conversations' })}
                </div>
                {hasConversations ? (
                  conversations.map((conversation) => (
                    <div key={conversation.id} className="rounded-lg border border-[var(--border)] bg-[var(--card)] overflow-hidden">
                      <div className="flex items-center justify-between p-3 bg-[var(--card-hover)] border-b border-[var(--border)]">
                        <div className="text-sm font-medium text-[var(--foreground)]">
                          {conversation.mailbox.email}
                        </div>
                        <span className="text-xs text-[var(--foreground-subtle)] capitalize">{conversation.status}</span>
                      </div>
                      <div className="p-3">
                        {conversation.thread.length > 0 ? (
                          conversation.thread.map((message, index) => (
                            <ThreadMessage
                              key={`${message.source || 'thread'}-${message.id}`}
                              message={message}
                              previousMessage={index > 0 ? conversation.thread[index - 1] : undefined}
                            />
                          ))
                        ) : (
                          <p className="text-sm text-[var(--foreground-subtle)]">
                            {t('admin.leads.modal.messages.no_thread', { defaultValue: 'No messages in this thread yet.' })}
                          </p>
                        )}
                      </div>
                    </div>
                  ))
                ) : (
                  <p className="text-sm text-[var(--foreground-subtle)]">
                    {t('admin.leads.modal.messages.no_conversations', { defaultValue: 'No conversations yet.' })}
                  </p>
                )}
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  )
}
