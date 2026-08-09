// Customer-facing playbook list page
// Displays all playbooks as gradient cards with filtering by status and product
import { Link, usePage } from '@inertiajs/react'
import AuthenticatedLayout from '../../layouts/AuthenticatedLayout'
import { t } from '../../lib/i18n'
import { Card, CardTitle, CardContent } from '../../components/ui/Card'
import { Badge } from '../../components/ui/Badge'
import { BookOpen } from 'lucide-react'

const GRADIENT_COLORS = ['orange', 'green', 'blue', 'purple'] as const
type GradientColor = (typeof GRADIENT_COLORS)[number]

function getPlaybookGradient(playbookId: number): GradientColor {
  return GRADIENT_COLORS[playbookId % GRADIENT_COLORS.length]
}

function getStatusBadgeVariant(status: string) {
  switch (status) {
    case 'draft':
      return 'draft' as const
    case 'changes_requested':
      return 'warning' as const
    case 'approved':
      return 'approved' as const
    case 'archived':
      return 'error' as const
    default:
      return 'default' as const
  }
}

interface ApprovedBy {
  id: number
  first_name: string
  last_name: string
  full_name: string
}

interface Playbook {
  id: number
  product: {
    name: string
    description: string
  }
  status: string
  language: string
  created_at: string
  updated_at: string
  approved_at: string | null
  approved_by: ApprovedBy | null
  persona_count: number
  use_case_count: number
  reference_count: number
  proof_point_count: number
}

interface PlaybooksIndexProps {
  playbooks: Playbook[]
  organization_website?: string | null
  canCreatePlaybook?: boolean
}

interface SharedProps {
  [key: string]: unknown
  auth: {
    account: {
      id: number
      email: string
      first_name: string
      last_name: string
      full_name: string
      role: string
    }
    organization?: {
      id: number
      name: string
    }
  }
  flash?: {
    notice?: string
    alert?: string
  }
  impersonating?: boolean
  impersonating_admin?: {
    id: number
    name: string
    email: string
  }
}

export default function Index({ playbooks }: PlaybooksIndexProps) {
  const { auth, flash } = usePage<SharedProps>().props
  const { account, organization } = auth

  return (
    <AuthenticatedLayout
      title={t('playbooks.title')}
      account={account}
      organization={organization}
      flash={flash}
    >
      {/* Playbooks Grid */}
      {playbooks.length === 0 ? (
        <Card className="!py-0">
          <CardContent className="p-12 text-center">
            <BookOpen className="mx-auto h-12 w-12 text-[var(--foreground-subtle)]" />
            <h3 className="mt-4 text-lg font-medium text-[var(--foreground)]">{t('playbooks.title')}</h3>
            <p className="mt-2 text-sm text-[var(--foreground-muted)]">{t('playbooks.empty')}</p>
          </CardContent>
        </Card>
      ) : (
        <div className="grid grid-cols-1 gap-5 md:grid-cols-2 lg:grid-cols-3">
          {playbooks.map((playbook) => (
            <Link key={playbook.id} href={`/playbooks/${playbook.id}`} className="block group">
              <Card
                variant="playbook"
                gradient={getPlaybookGradient(playbook.id)}
                className="h-full min-h-[200px] group-hover:scale-[1.02] transition-transform duration-200"
              >
                <div className="flex items-center gap-2">
                  <Badge variant={getStatusBadgeVariant(playbook.status)}>
                    {t(`playbooks.statuses.${playbook.status}`)}
                  </Badge>
                  <Badge variant="outline">
                    {playbook.language.toUpperCase()}
                  </Badge>
                </div>
                <div>
                  <p className="text-sm text-white/60 mb-1">
                    {playbook.persona_count} {t('playbooks.table.personae')} · {playbook.use_case_count} {t('playbooks.table.use_cases')}
                  </p>
                  <CardTitle>{playbook.product.name}</CardTitle>
                  {playbook.product.description && (
                    <p className="mt-1 text-sm text-white/50 line-clamp-2">
                      {playbook.product.description}
                    </p>
                  )}
                </div>
              </Card>
            </Link>
          ))}
        </div>
      )}
    </AuthenticatedLayout>
  )
}
