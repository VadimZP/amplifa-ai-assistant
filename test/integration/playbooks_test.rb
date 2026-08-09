require 'test_helper'

class PlaybooksTest < ActionDispatch::IntegrationTest
  # because customers have different permissions and workflow actions than admins.
  # Customers can view, approve, request changes, and archive playbooks for their org only.

  def setup
    @customer_admin = accounts(:customer_admin)
    @customer_user = accounts(:customer_user)
    @amplifa_admin = accounts(:amplifa_admin)

    @org = organizations(:acme)
    @playbook_draft = playbooks(:draft_playbook)
    @playbook_approved = playbooks(:approved_playbook)

    # to verify that customers cannot access other organizations' playbooks
    @other_org = organizations(:beta)
    @other_playbook = playbooks(:other_org_playbook)
  end

  test 'customer admin can view playbooks index for their organization' do
    # belonging to their organization
    login_as(@customer_admin)

    get playbooks_path, headers: inertia_headers
    assert_response :success
    assert_inertia_component 'Playbooks/Index'

    props = inertia_props
    assert props['playbooks'].is_a?(Array)

    props['playbooks'].each do |pb|
      refute_nil pb['id']
      # Some playbooks may not have organization serialized in minimal list view
    end
  end

  test 'customer user can view playbooks index for their organization' do
    login_as(@customer_user)

    get playbooks_path, headers: inertia_headers
    assert_response :success
    assert_inertia_component 'Playbooks/Index'
  end

  test 'playbooks index filters by status parameter' do
    # to quickly find draft, approved, or archived playbooks
    login_as(@customer_admin)

    get playbooks_path, params: { status: 'draft' }, headers: inertia_headers
    assert_response :success

    props = inertia_props
    assert_equal 'draft', props['filters']['status']
  end

  test 'playbooks index filters by product parameter' do
    # filter playbooks by specific product (now by name instead of ID)
    login_as(@customer_admin)

    product_name = @playbook_draft.product_name
    get playbooks_path, params: { product_name: product_name }, headers: inertia_headers
    assert_response :success

    props = inertia_props
    assert_equal product_name, props['filters']['product_name']
  end

  test "playbooks index only shows customer's organization playbooks" do
    # from other organizations
    login_as(@customer_admin)

    get playbooks_path, headers: inertia_headers
    assert_response :success

    props = inertia_props
    playbook_ids = props['playbooks'].map { |pb| pb['id'] }

    refute_includes playbook_ids, @other_playbook.id
  end

  test 'unauthenticated user cannot access playbooks index' do
    get playbooks_path
    assert_response :redirect
    assert_redirected_to login_path
  end

  test 'customer admin can view playbook detail page' do
    # including personae, use cases, references, proof points, and comments
    login_as(@customer_admin)

    get playbook_path(@playbook_draft), headers: inertia_headers
    assert_response :success
    assert_inertia_component 'Playbooks/Show'

    props = inertia_props
    assert_equal @playbook_draft.id, props['playbook']['id']

    assert props['playbook']['personae'].is_a?(Array)
    assert props['playbook']['use_cases'].is_a?(Array)
    assert props['playbook']['references'].is_a?(Array)
    assert props['playbook']['proof_points'].is_a?(Array)

    assert props['comments'].is_a?(Array)

    assert_includes props.keys, 'canApprove'
    assert_includes props.keys, 'canRequestChanges'
    assert_includes props.keys, 'canArchive'
  end

  test 'customer user can view playbook detail page' do
    login_as(@customer_user)

    get playbook_path(@playbook_draft), headers: inertia_headers
    assert_response :success
    assert_inertia_component 'Playbooks/Show'
  end

  test 'customer admin can update editable playbook text section' do
    login_as(@customer_admin)

    patch playbook_path(@playbook_draft), params: {
      playbook: {
        value_proposition: 'Updated customer-facing value proposition'
      }
    }

    assert_redirected_to playbook_path(@playbook_draft)
    assert_equal 'Updated customer-facing value proposition', @playbook_draft.reload.value_proposition
  end

  test 'customer admin can update editable playbook product description' do
    login_as(@customer_admin)

    patch playbook_path(@playbook_draft), params: {
      playbook: {
        product: @playbook_draft.product.merge('description' => 'Updated customer-facing product description')
      }
    }

    assert_redirected_to playbook_path(@playbook_draft)
    assert_equal 'Updated customer-facing product description', @playbook_draft.reload.product['description']
  end

  test 'customer admin can update editable playbook multi-item section' do
    login_as(@customer_admin)
    original_use_case = @playbook_draft.use_cases.first

    patch playbook_path(@playbook_draft), params: {
      playbook: {
        use_cases: [
          original_use_case.merge('title' => 'Updated use case title'),
          {
            id: 'customer-added-use-case',
            title: 'Customer added use case',
            description: 'Created from the section edit modal.',
            order: 2
          }
        ]
      }
    }

    assert_redirected_to playbook_path(@playbook_draft)
    use_case_titles = @playbook_draft.reload.use_cases.map { |item| item['title'] }
    assert_equal ['Updated use case title', 'Customer added use case'], use_case_titles
  end

  test 'customer admin can add items to all editable playbook subsection sections' do
    login_as(@customer_admin)

    patch playbook_path(@playbook_draft), params: {
      playbook: {
        personae: @playbook_draft.personae + [{
          id: 'customer-added-persona',
          name: 'Customer added persona',
          title: 'Buyer title',
          order: @playbook_draft.personae.length + 1,
          pain_points: ['New pain point']
        }],
        use_cases: @playbook_draft.use_cases + [{
          id: 'customer-added-use-case-all',
          title: 'Customer added use case',
          description: 'Created from modal add.',
          order: @playbook_draft.use_cases.length + 1
        }],
        references: @playbook_draft.references + [{
          id: 'customer-added-reference',
          customer_name: 'Customer added reference',
          description: 'Reference details from modal add.',
          order: @playbook_draft.references.length + 1
        }],
        proof_points: @playbook_draft.proof_points + [{
          id: 'customer-added-proof-point',
          claim: 'Customer added proof point',
          description: 'Proof point details from modal add.',
          order: @playbook_draft.proof_points.length + 1
        }]
      }
    }

    assert_redirected_to playbook_path(@playbook_draft)
    @playbook_draft.reload

    assert_includes @playbook_draft.personae.map { |item| item['name'] }, 'Customer added persona'
    assert_includes @playbook_draft.use_cases.map { |item| item['title'] }, 'Customer added use case'
    assert_includes @playbook_draft.references.map { |item| item['customer_name'] }, 'Customer added reference'
    assert_includes @playbook_draft.proof_points.map { |item| item['claim'] }, 'Customer added proof point'
  end

  test "customer cannot view other organization's playbook" do
    # from other organizations, even if they have the ID
    login_as(@customer_admin)

    get playbook_path(@other_playbook), headers: inertia_headers
    assert_response :not_found
  end

  test 'show action includes permission flags based on user role' do
    login_as(@customer_admin)

    get playbook_path(@playbook_draft), headers: inertia_headers
    assert_response :success

    props = inertia_props

    assert props['canApprove'], 'Customer admin should be able to approve'
    assert props['canRequestChanges'], 'Customer admin should be able to request changes'
    assert props['canArchive'], 'Customer admin should be able to archive'
  end

  test 'customer admin can approve a draft playbook' do
    # This transitions status to 'approved' and records approval metadata
    login_as(@customer_admin)

    assert_difference 'PlaybookComment.count', 1 do
      post approve_playbook_path(@playbook_draft), params: {
        comment: 'Looks great, approved!'
      }
    end

    assert_redirected_to playbook_path(@playbook_draft)
    assert_match(/approved successfully/i, flash[:notice])

    @playbook_draft.reload
    assert_equal 'approved', @playbook_draft.status
    assert_not_nil @playbook_draft.approved_at
    assert_equal @customer_admin.id, @playbook_draft.approved_by_id

    comment = @playbook_draft.playbook_comments.last
    assert_equal 'approval', comment.comment_type
    assert_equal @customer_admin.id, comment.account_id
  end

  test 'approving playbook also approves linked generated samples' do
    agent = agents(:draft_agent)
    agent.update!(samples_generated_at: 1.hour.ago, samples_approved_at: nil, samples_approved_by: nil)
    generated_messages(:john_step_one_draft).update!(sample: true)
    generated_messages(:john_step_two_draft).update!(sample: true)

    login_as(@customer_admin)

    assert agent.sample_messages.where(status: 'draft').exists?

    post approve_playbook_path(@playbook_draft), headers: inertia_headers

    assert_redirected_to playbook_path(@playbook_draft)

    @playbook_draft.reload
    agent.reload

    assert_equal 'approved', @playbook_draft.status
    assert agent.samples_approved?
    assert_equal @customer_admin.id, agent.samples_approved_by_id
    assert_equal 0, agent.sample_messages.where(status: 'draft').count
  end

  test 'customer user can approve a draft playbook' do
    # playbooks for flexibility in the approval process
    login_as(@customer_user)

    post approve_playbook_path(@playbook_draft)

    assert_redirected_to playbook_path(@playbook_draft)
    @playbook_draft.reload
    assert_equal 'approved', @playbook_draft.status
  end

  test 'approve action accepts optional comment' do
    # to provide context or feedback
    login_as(@customer_admin)

    post approve_playbook_path(@playbook_draft), params: {
      comment: 'Perfect, exactly what we need!'
    }

    comment = @playbook_draft.playbook_comments.last
    assert_equal 'Perfect, exactly what we need!', comment.body
  end

  test 'approve action logs admin activity' do
    login_as(@customer_admin)

    assert_difference 'AdminActivity.count', 1 do
      post approve_playbook_path(@playbook_draft)
    end

    activity = AdminActivity.last
    assert_equal 'playbook_approved', activity.action
    assert_equal @customer_admin.id, activity.account_id
    assert_equal @org.id, activity.organization_id
    assert_equal @playbook_draft.id, activity.details['playbook_id']
  end

  test 'amplifa admin cannot approve playbook' do
    # Admins should not approve on behalf of customers.
    login_as(@amplifa_admin)

    post approve_playbook_path(@playbook_draft)
    assert_redirected_to root_path
    follow_redirect!
    assert_match(/not authorized/i, flash[:alert])
  end

  test "customer cannot approve other organization's playbook" do
    # playbooks belonging to their own organization
    login_as(@customer_admin)

    post approve_playbook_path(@other_playbook)
    assert_response :not_found
  end

  test 'customer cannot approve already approved playbook' do
    # The policy should prevent this action.
    login_as(@customer_admin)

    # First, ensure the playbook is approved
    @playbook_draft.approve!(@customer_admin)

    post approve_playbook_path(@playbook_draft)
    assert_redirected_to root_path
    follow_redirect!
    assert_match(/not authorized/i, flash[:alert])
  end

  test 'customer admin can request changes on draft playbook' do
    # doesn't meet their expectations
    login_as(@customer_admin)

    assert_difference 'PlaybookComment.count', 1 do
      post request_changes_playbook_path(@playbook_draft), params: {
        comment: 'Please add more personae targeting CTOs'
      }
    end

    assert_redirected_to playbook_path(@playbook_draft)
    assert_match(/changes requested/i, flash[:notice])

    @playbook_draft.reload
    assert_equal 'changes_requested', @playbook_draft.status

    assert_nil @playbook_draft.approved_at
    assert_nil @playbook_draft.approved_by_id

    comment = @playbook_draft.playbook_comments.last
    assert_equal 'request_changes', comment.comment_type
    assert_equal 'Please add more personae targeting CTOs', comment.body
  end

  test 'customer user can request changes on draft playbook' do
    login_as(@customer_user)

    post request_changes_playbook_path(@playbook_draft), params: {
      comment: 'Needs revision'
    }

    assert_redirected_to playbook_path(@playbook_draft)
    @playbook_draft.reload
    assert_equal 'changes_requested', @playbook_draft.status
  end

  test 'request changes stores feedback context for selected sample message' do
    login_as(@customer_admin)
    message = generated_messages(:john_step_one_draft)
    lead = message.agent_lead.lead
    agent = message.agent_lead.agent

    post request_changes_playbook_path(@playbook_draft), params: {
      comment: 'Please adjust this sample message',
      feedback_context: {
        tab: 'samples',
        lead_id: lead.id,
        lead_name: lead.display_name,
        message_id: message.id,
        step_label: message.sequence_step.display_name,
        step_position: message.sequence_step.position,
        agent_id: agent.id,
        agent_name: agent.name
      }
    }

    comment = @playbook_draft.playbook_comments.last
    assert_equal 'samples', comment.feedback_context['tab']
    assert_equal lead.id, comment.feedback_context['lead_id']
    assert_equal message.id, comment.feedback_context['message_id']
    assert_equal agent.id, comment.feedback_context['agent_id']
  end

  test 'request changes requires comment' do
    # explaining what needs to be changed
    login_as(@customer_admin)

    post request_changes_playbook_path(@playbook_draft), params: {
      comment: ''
    }

    assert_redirected_to playbook_path(@playbook_draft)
    assert_match(/provide a comment/i, flash[:alert])

    @playbook_draft.reload
    assert_equal 'draft', @playbook_draft.status
  end

  test 'request changes logs admin activity' do
    login_as(@customer_admin)

    assert_difference 'AdminActivity.count', 1 do
      post request_changes_playbook_path(@playbook_draft), params: {
        comment: 'Needs more detail'
      }
    end

    activity = AdminActivity.last
    assert_equal 'playbook_changes_requested', activity.action
    assert_equal @customer_admin.id, activity.account_id
  end

  test 'amplifa admin cannot request changes' do
    login_as(@amplifa_admin)

    post request_changes_playbook_path(@playbook_draft), params: {
      comment: 'Change this'
    }
    assert_redirected_to root_path
    follow_redirect!
    assert_match(/not authorized/i, flash[:alert])
  end

  test "customer cannot request changes on other organization's playbook" do
    login_as(@customer_admin)

    post request_changes_playbook_path(@other_playbook), params: {
      comment: 'Change this'
    }
    assert_response :not_found
  end

  test 'customer admin can archive playbook' do
    login_as(@customer_admin)

    post archive_playbook_path(@playbook_draft)

    assert_redirected_to playbooks_path
    assert_match(/archived/i, flash[:notice])

    @playbook_draft.reload
    assert_equal 'archived', @playbook_draft.status
  end

  test 'show action includes feedback context in comments props' do
    login_as(@customer_admin)
    message = generated_messages(:john_step_one_draft)

    comment = @playbook_draft.playbook_comments.create!(
      account: @customer_admin,
      body: 'Please revise this message',
      comment_type: 'request_changes',
      feedback_context: {
        tab: 'samples',
        lead_id: message.agent_lead.lead_id,
        lead_name: message.agent_lead.lead.display_name,
        message_id: message.id,
        step_label: message.sequence_step.display_name,
        step_position: message.sequence_step.position,
        agent_id: message.agent_lead.agent_id,
        agent_name: message.agent_lead.agent.name
      }
    )

    get playbook_path(@playbook_draft), headers: inertia_headers

    serialized_comment = inertia_props['comments'].find { |entry| entry['id'] == comment.id }
    assert_equal 'samples', serialized_comment['feedback_context']['tab']
    assert_equal message.id, serialized_comment['feedback_context']['message_id']
  end

  test 'archive action logs admin activity' do
    login_as(@customer_admin)

    assert_difference 'AdminActivity.count', 1 do
      post archive_playbook_path(@playbook_draft)
    end

    activity = AdminActivity.last
    assert_equal 'playbook_archived', activity.action
  end

  test 'customer user cannot archive playbook' do
    login_as(@customer_user)

    post archive_playbook_path(@playbook_draft)
    assert_redirected_to root_path
    follow_redirect!
    assert_match(/not authorized/i, flash[:alert])
  end

  test 'amplifa admin can archive playbook through customer route' do
    # While they typically use the admin route, the customer route works too
    login_as(@amplifa_admin)

    post archive_playbook_path(@playbook_draft)
    assert_redirected_to playbooks_path
    assert_match(/archived/i, flash[:notice])

    @playbook_draft.reload
    assert_equal 'archived', @playbook_draft.status
  end

  test "customer cannot archive other organization's playbook" do
    login_as(@customer_admin)

    post archive_playbook_path(@other_playbook)
    assert_response :not_found
  end

  test "policy scope ensures customers only see their organization's playbooks" do
    # correctly scopes playbooks to the customer's organization
    login_as(@customer_admin)

    scoped = Pundit.policy_scope(@customer_admin, Playbook)

    scoped.each do |playbook|
      assert_equal @org.id, playbook.organization_id,
                   'Policy scope returned playbook from wrong organization'
    end

    refute_includes scoped.ids, @other_playbook.id,
                    "Policy scope should not include other organization's playbooks"
  end

  test 'customer can upload file to reference on editable playbook' do
    # to playbook references when the playbook is in draft or changes_requested status
    login_as(@customer_admin)

    reference_id = SecureRandom.uuid
    @playbook_draft.update!(
      references: [
        {
          'id' => reference_id,
          'customer_name' => 'Customer Reference',
          'description' => 'Success story',
          'order' => 1
        }
      ]
    )

    file = fixture_file_upload('sample.pdf', 'application/pdf')
    post upload_file_playbook_path(@playbook_draft), params: {
      file: file,
      file_type: 'reference',
      item_id: reference_id
    }

    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response['file_url'].present?
    assert_equal 'sample.pdf', json_response['file_name']

    # Verify file was saved to playbook
    @playbook_draft.reload
    reference = @playbook_draft.references.find { |r| r['id'] == reference_id }
    assert reference['file_url'].present?
  end

  test 'customer can upload file to proof point on editable playbook' do
    login_as(@customer_admin)

    proof_point_id = SecureRandom.uuid
    @playbook_draft.update!(
      proof_points: [
        {
          'id' => proof_point_id,
          'claim' => 'ROI Proof',
          'description' => 'Documented results',
          'order' => 1
        }
      ]
    )

    file = fixture_file_upload('sample.pdf', 'application/pdf')
    post upload_file_playbook_path(@playbook_draft), params: {
      file: file,
      file_type: 'proof_point',
      item_id: proof_point_id
    }

    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response['file_url'].present?

    @playbook_draft.reload
    proof_point = @playbook_draft.proof_points.find { |p| p['id'] == proof_point_id }
    assert proof_point['file_url'].present?
  end

  test 'customer cannot upload file to approved playbook' do
    login_as(@customer_admin)

    reference_id = SecureRandom.uuid
    @playbook_approved.update!(
      references: [{ 'id' => reference_id, 'customer_name' => 'Test', 'description' => 'Test', 'order' => 1 }]
    )

    file = fixture_file_upload('sample.pdf', 'application/pdf')
    post upload_file_playbook_path(@playbook_approved), params: {
      file: file,
      file_type: 'reference',
      item_id: reference_id
    }

    # Should be forbidden since approved playbooks aren't editable
    assert_redirected_to root_path
  end

  test "customer cannot upload file to other organization's playbook" do
    login_as(@customer_admin)

    post upload_file_playbook_path(@other_playbook), params: {
      file: fixture_file_upload('sample.pdf', 'application/pdf'),
      file_type: 'reference',
      item_id: 'some-id'
    }

    # Should get 404 since policy_scope filters out other org's playbooks
    assert_response :not_found
  end

  test 'show page includes canUploadFiles permission flag' do
    login_as(@customer_admin)

    get playbook_path(@playbook_draft), headers: inertia_headers
    assert_response :success

    props = inertia_props
    assert props.key?('canUploadFiles'), 'Props should include canUploadFiles flag'
    # Draft playbook should be editable, so uploads should be allowed
    assert_equal true, props['canUploadFiles']
  end

end
