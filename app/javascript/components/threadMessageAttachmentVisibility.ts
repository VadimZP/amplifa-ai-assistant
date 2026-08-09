export interface VisibleThreadAttachment {
  filename: string
  content_type: string
}

const OFFICE_MIME_TYPES = [
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation'
]

const ALLOWED_ATTACHMENT_EXTENSIONS = ['.ics', '.pdf', '.docx', '.xlsx', '.pptx', '.csv']
const IMAGE_EXTENSIONS = ['.png', '.jpg', '.jpeg', '.gif', '.webp']

export const ALLOWED_REPLY_ATTACHMENT_ACCEPT = ALLOWED_ATTACHMENT_EXTENSIONS.join(',')

interface AllowedReplyAttachmentFileLike {
  name: string
  type: string
}

export function isCalendarInviteAttachment(attachment: VisibleThreadAttachment) {
  return attachment.content_type === 'text/calendar' || attachment.filename.toLowerCase().endsWith('.ics')
}

export function isPdfThreadAttachment(attachment: VisibleThreadAttachment) {
  return attachment.content_type === 'application/pdf' || attachment.filename.toLowerCase().endsWith('.pdf')
}

export function isOfficeThreadAttachment(attachment: VisibleThreadAttachment) {
  const filename = attachment.filename.toLowerCase()

  return OFFICE_MIME_TYPES.includes(attachment.content_type) ||
    filename.endsWith('.docx') ||
    filename.endsWith('.xlsx') ||
    filename.endsWith('.pptx')
}

export function isCsvThreadAttachment(attachment: VisibleThreadAttachment) {
  return attachment.content_type === 'text/csv' || attachment.filename.toLowerCase().endsWith('.csv')
}

export function isImageThreadAttachment(attachment: VisibleThreadAttachment) {
  const filename = attachment.filename.toLowerCase()

  return attachment.content_type.toLowerCase().startsWith('image/') ||
    IMAGE_EXTENSIONS.some((extension) => filename.endsWith(extension))
}

export function isAllowedReplyAttachmentFile(file: AllowedReplyAttachmentFileLike) {
  const filename = file.name.toLowerCase()

  return file.type === 'text/calendar' ||
    file.type === 'application/pdf' ||
    file.type === 'text/csv' ||
    OFFICE_MIME_TYPES.includes(file.type) ||
    ALLOWED_ATTACHMENT_EXTENSIONS.some((extension) => filename.endsWith(extension))
}

export function shouldShowThreadAttachment(attachment: VisibleThreadAttachment) {
  return isCalendarInviteAttachment(attachment) ||
    isPdfThreadAttachment(attachment) ||
    isOfficeThreadAttachment(attachment) ||
    isCsvThreadAttachment(attachment) ||
    isImageThreadAttachment(attachment)
}
