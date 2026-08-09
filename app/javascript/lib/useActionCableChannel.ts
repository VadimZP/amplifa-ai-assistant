import { useEffect, useRef } from 'react'
import { cable } from './actioncable'

interface ChannelParams {
  channel: string
  [key: string]: unknown
}

interface ChannelHandlers<T = unknown> {
  received?: (data: T) => void
  connected?: () => void
  disconnected?: () => void
  rejected?: () => void
}

export function useActionCableChannel<T = unknown>(
  params: ChannelParams,
  handlers: ChannelHandlers<T>
) {
  const handlersRef = useRef(handlers)
  handlersRef.current = handlers

  const paramsKey = JSON.stringify(params)
  const canSubscribe = Object.values(params).every(value => value !== null && value !== undefined)

  useEffect(() => {
    if (!canSubscribe) return undefined

    const subscription = cable.subscriptions.create(params, {
      received(data: T) {
        handlersRef.current.received?.(data)
      },
      connected() {
        handlersRef.current.connected?.()
      },
      disconnected() {
        handlersRef.current.disconnected?.()
      },
      rejected() {
        handlersRef.current.rejected?.()
      },
    })

    return () => {
      subscription.unsubscribe()
    }
  }, [canSubscribe, paramsKey])
}
