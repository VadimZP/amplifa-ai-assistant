import { useEffect, useRef } from 'react'
import { RefreshCw, Check } from 'lucide-react'
import { t } from '../lib/i18n'

interface GenerationProgressProps {
  total: number
  completed: number
  errors: number
  isComplete: boolean
  onComplete?: () => void
}

export default function GenerationProgress({
  total,
  completed,
  errors,
  isComplete,
  onComplete,
}: GenerationProgressProps) {
  const onCompleteRef = useRef(onComplete)
  onCompleteRef.current = onComplete

  useEffect(() => {
    if (isComplete) {
      onCompleteRef.current?.()
      return
    }

    const interval = setInterval(() => {
    }, 2000)

    return () => clearInterval(interval)
  }, [isComplete])

  const percentage = total > 0 ? Math.round((completed / total) * 100) : 0

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between text-sm">
        <span className="text-gray-700">
          {t('components.generation_progress.completed', { completed, total })}
        </span>
        <div className="flex items-center gap-2">
          {errors > 0 && (
            <span className="text-red-600">
              {t('components.generation_progress.errors', { count: errors })}
            </span>
          )}
          {isComplete ? (
            <Check className="h-4 w-4 text-green-600" />
          ) : (
            <RefreshCw className="h-4 w-4 text-indigo-600 animate-spin" />
          )}
        </div>
      </div>
      <div className="w-full bg-gray-200 rounded-full h-2">
        <div
          className="bg-indigo-600 h-2 rounded-full transition-all duration-300"
          style={{ width: `${percentage}%` }}
        />
      </div>
      <div className="text-xs text-gray-500 text-right">{percentage}%</div>
    </div>
  )
}
