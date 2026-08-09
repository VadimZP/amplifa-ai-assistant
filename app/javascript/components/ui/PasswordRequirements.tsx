import { CircleCheck } from 'lucide-react'
import { t } from '../../lib/i18n'

interface PasswordRequirementsProps {
  password: string
  className?: string
  // WHY: Optional locale prop triggers re-render when language changes on the fly
  // (e.g. on the invitation accept screen). The t() calls inside the component
  // will use the updated i18n.locale on re-render.
  locale?: string
}

export function PasswordRequirements({ password, className = '' }: PasswordRequirementsProps) {
  // WHY: Requirements are defined inside the component so t() calls re-evaluate
  // on each render, picking up locale changes for on-the-fly translation.
  const requirements = [
    { key: 'length', label: t('invitation.accept.password_req_length'), test: (p: string) => p.length >= 8 },
    { key: 'uppercase', label: t('invitation.accept.password_req_uppercase'), test: (p: string) => /[A-Z]/.test(p) },
    { key: 'lowercase', label: t('invitation.accept.password_req_lowercase'), test: (p: string) => /[a-z]/.test(p) },
    { key: 'number', label: t('invitation.accept.password_req_number'), test: (p: string) => /[0-9]/.test(p) },
  ]

  return (
    <div className={`flex flex-col gap-3 ${className}`}>
      {requirements.map((req) => {
        const met = req.test(password)
        return (
          <div key={req.key} className="flex items-center gap-2">
            <CircleCheck
              size={16}
              className={`transition-colors duration-150 ${
                met ? 'text-[var(--success)]' : 'text-[var(--validation-unchecked)]'
              }`}
            />
            <span
              className={`text-xs transition-colors duration-150 ${
                met ? 'text-[var(--foreground)]' : 'text-[var(--validation-unchecked)]'
              }`}
            >
              {req.label}
            </span>
          </div>
        )
      })}
    </div>
  )
}

export default PasswordRequirements
