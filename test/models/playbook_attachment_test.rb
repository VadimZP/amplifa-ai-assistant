require 'test_helper'

class PlaybookAttachmentTest < ActiveSupport::TestCase
  test 'requires playbook' do
    attachment = build_attachment(playbook: nil)

    assert_not attachment.valid?
    assert_includes attachment.errors[:playbook], "can't be blank"
  end

  test 'validates attachable_type inclusion' do
    %w[reference proof_point].each do |attachable_type|
      attachment = build_attachment(attachable_type: attachable_type)

      assert attachment.valid?, "Expected #{attachable_type} to be valid"
    end

    attachment = build_attachment(attachable_type: 'invalid')

    assert_not attachment.valid?
    assert_includes attachment.errors[:attachable_type], 'is not included in the list'
  end

  test 'requires attachable_id' do
    attachment = build_attachment(attachable_id: nil)

    assert_not attachment.valid?
    assert_includes attachment.errors[:attachable_id], "can't be blank"
  end

  test 'requires original_filename' do
    attachment = build_attachment(original_filename: nil)

    assert_not attachment.valid?
    assert_includes attachment.errors[:original_filename], "can't be blank"
  end

  test 'requires file to be attached' do
    attachment = PlaybookAttachment.new(
      playbook: playbooks(:playbook_with_references),
      attachable_type: 'reference',
      attachable_id: 'ref-attachment-test',
      original_filename: 'sample.pdf',
      content_type: 'application/pdf',
      file_size_bytes: 1.kilobyte
    )

    assert_not attachment.valid?
    assert_includes attachment.errors[:file], 'must be attached'
  end

  test 'defaults extraction_status to pending' do
    attachment = build_attachment

    attachment.save!

    assert_equal 'pending', attachment.reload.extraction_status
  end

  test 'validates extraction_status inclusion' do
    attachment = build_attachment(extraction_status: 'nope')

    assert_not attachment.valid?
    assert_includes attachment.errors[:extraction_status], 'is not included in the list'
  end

  test 'for_playbook scope returns attachments for the given playbook' do
    matching_attachment = create_attachment(
      playbook: playbooks(:playbook_with_references),
      attachable_id: 'ref-scope-match'
    )
    other_attachment = create_attachment(
      playbook: playbooks(:draft_playbook),
      attachable_id: 'ref-scope-other'
    )

    attachments = PlaybookAttachment.for_playbook(playbooks(:playbook_with_references))

    assert_includes attachments, matching_attachment
    assert_not_includes attachments, other_attachment
  end

  test 'for_references and for_proof_points scopes filter by attachable_type' do
    reference_attachment = create_attachment(
      playbook: playbooks(:playbook_with_references),
      attachable_type: 'reference',
      attachable_id: 'ref-type-scope'
    )
    proof_point_attachment = create_attachment(
      playbook: playbooks(:playbook_with_references),
      attachable_type: 'proof_point',
      attachable_id: 'pp-type-scope'
    )

    assert_includes PlaybookAttachment.for_references, reference_attachment
    assert_not_includes PlaybookAttachment.for_references, proof_point_attachment
    assert_includes PlaybookAttachment.for_proof_points, proof_point_attachment
    assert_not_includes PlaybookAttachment.for_proof_points, reference_attachment
  end

  test 'with_extraction_status scope filters by extraction_status' do
    completed_attachment = create_attachment(
      playbook: playbooks(:playbook_with_references),
      attachable_id: 'ref-completed-scope',
      extraction_status: 'completed'
    )
    pending_attachment = create_attachment(
      playbook: playbooks(:playbook_with_references),
      attachable_id: 'ref-pending-scope',
      extraction_status: 'pending'
    )

    attachments = PlaybookAttachment.with_extraction_status('completed')

    assert_includes attachments, completed_attachment
    assert_not_includes attachments, pending_attachment
  end

  test 'playbook destroys dependent attachments' do
    playbook = playbooks(:playbook_with_references)
    attachment = create_attachment(playbook: playbook, attachable_id: 'ref-dependent-destroy')

    assert_difference('PlaybookAttachment.count', -1) do
      playbook.destroy
    end

    assert_not PlaybookAttachment.exists?(attachment.id)
  end

  test 'knowledge base attachment can apply to all playbooks without a specific playbook' do
    attachment = build_knowledge_base_attachment(applies_to_all_playbooks: true)

    assert attachment.valid?
    attachment.save!

    assert attachment.applies_to_all_playbooks?
    assert_empty attachment.assigned_playbooks
  end

  test 'knowledge base attachment can apply to selected playbooks' do
    playbook = playbooks(:playbook_with_references)
    attachment = build_knowledge_base_attachment(applies_to_all_playbooks: false)
    attachment.assigned_playbooks = [playbook]

    assert attachment.valid?
    attachment.save!

    assert_equal [playbook.id], attachment.assigned_playbook_ids
  end

  test 'knowledge base scope returns all and selected attachments for playbook' do
    playbook = playbooks(:playbook_with_references)
    all_attachment = build_knowledge_base_attachment(applies_to_all_playbooks: true, attachable_id: 'kb-all')
    selected_attachment = build_knowledge_base_attachment(applies_to_all_playbooks: false, attachable_id: 'kb-selected')
    other_attachment = build_knowledge_base_attachment(applies_to_all_playbooks: false, attachable_id: 'kb-other')

    all_attachment.save!
    selected_attachment.assigned_playbooks = [playbook]
    selected_attachment.save!
    other_attachment.assigned_playbooks = [playbooks(:draft_playbook)]
    other_attachment.save!

    attachments = PlaybookAttachment.knowledge_base.for_playbook_or_all(playbook)

    assert_includes attachments, all_attachment
    assert_includes attachments, selected_attachment
    assert_not_includes attachments, other_attachment
  end

  private

  def build_attachment(playbook: playbooks(:playbook_with_references), **attributes)
    attachment = PlaybookAttachment.new(
      {
        playbook: playbook,
        attachable_type: 'reference',
        attachable_id: 'ref-build-attachment',
        original_filename: 'sample.pdf',
        content_type: 'application/pdf',
        file_size_bytes: 1.kilobyte,
        extraction_status: 'pending'
      }.merge(attributes)
    )

    attach_sample_file(attachment) unless attributes[:skip_file_attachment]
    attachment
  end

  def create_attachment(**attributes)
    attachment = build_attachment(**attributes)
    attachment.save!
    attachment
  end

  def build_knowledge_base_attachment(**attributes)
    attachment = PlaybookAttachment.new(
      {
        organization: organizations(:acme),
        uploaded_by: accounts(:amplifa_admin),
        attachable_type: 'knowledge_base',
        attachable_id: SecureRandom.uuid,
        original_filename: 'knowledge-base.txt',
        display_name: 'knowledge-base.txt',
        content_type: 'text/plain',
        file_size_bytes: 1.kilobyte,
        extraction_status: 'completed',
        source_type: 'file',
        extracted_text: 'Knowledge base material.'
      }.merge(attributes)
    )

    attachment.file.attach(
      io: StringIO.new('Knowledge base material.'),
      filename: attachment.original_filename || 'knowledge-base.txt',
      content_type: attachment.content_type || 'text/plain'
    )
    attachment
  end

  def attach_sample_file(attachment)
    attachment.file.attach(
      io: StringIO.new(File.binread(Rails.root.join('test/fixtures/files/sample.pdf'))),
      filename: attachment.original_filename || 'sample.pdf',
      content_type: attachment.content_type || 'application/pdf'
    )
  end
end
