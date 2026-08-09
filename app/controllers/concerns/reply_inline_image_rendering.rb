# frozen_string_literal: true

# Rewrites CID-referenced email images to ActiveStorage blob URLs for thread rendering.
module ReplyInlineImageRendering
  extend ActiveSupport::Concern

  private

  def body_html_with_inline_attachment_urls(html, attachments)
    return html if html.blank?

    attachments_by_content_id = inline_image_attachments_by_content_id(attachments)
    fragment = Nokogiri::HTML.fragment(html)
    remove_html_comments(fragment)
    rewrite_inline_image_nodes(fragment, attachments_by_content_id) if attachments_by_content_id.present?

    fragment.to_html.strip.presence || html
  end

  def body_html_for_thread_message(message)
    return message[:body_html] unless message[:source].to_s == 'reply'

    body_html_with_inline_attachment_urls(message[:body_html], message[:attachments])
  end

  def inline_image_attachment?(attachment)
    attachment[:content_id].present? && image_content_type?(attachment[:content_type])
  end

  def rewrite_inline_image_nodes(fragment, attachments_by_content_id)
    fragment.css('img[src]').each do |image_node|
      rewrite_inline_image_node(image_node, attachments_by_content_id[content_id_from_src(image_node['src'])])
    end

    fragment
  end

  def rewrite_inline_image_node(image_node, attachment)
    return unless attachment

    image_node['src'] = rails_blob_path(attachment[:file], disposition: 'inline', only_path: true)
    image_node['alt'] = attachment[:original_filename] if image_node['alt'].blank?
  end

  def remove_html_comments(fragment)
    comments = []
    fragment.traverse { |node| comments << node if node.comment? }
    comments.each(&:remove)
    fragment.css('style').each do |style_node|
      style_node.content = style_node.content
                                     .to_s
                                     .sub(/\A\s*<!--\s*/m, '')
                                     .sub(/\s*-->\s*\z/m, '')
    end
  end

  def html_references_attachment_content_id?(html, attachment)
    content_id = normalized_content_id(attachment[:content_id])
    return false if html.blank? || content_id.blank?

    content_ids_referenced_in_html(html).include?(content_id)
  end

  def content_ids_referenced_in_html(html)
    Nokogiri::HTML.fragment(html).css('img[src]').filter_map do |image_node|
      content_id_from_src(image_node['src'])
    end
  end

  def image_content_type?(content_type)
    content_type.to_s.downcase.start_with?('image/')
  end

  def normalized_content_id(content_id)
    content_id.to_s.strip.delete_prefix('<').delete_suffix('>').downcase.presence
  end

  def content_id_from_src(src)
    value = src.to_s.strip
    return nil unless value.match?(/\Acid:/i)

    normalized_content_id(CGI.unescape(value.sub(/\Acid:/i, '')))
  end

  def inline_image_attachments_by_content_id(attachments)
    Array(attachments).each_with_object({}) do |attachment, index|
      next unless inline_image_attachment?(attachment)

      content_id = normalized_content_id(attachment[:content_id])
      next if content_id.blank? || attachment[:file].blank?

      index[content_id] = attachment
    end
  end
end
