# frozen_string_literal: true

Rails.application.routes.draw do
  mount ActionCable.server => '/cable'

  root 'pages#home'

  # Sessions
  get 'login', to: 'sessions#new'
  post 'login', to: 'sessions#create'
  post 'logout', to: 'sessions#destroy'
  get 'two-factor-email', to: 'email_two_factor_challenges#show', as: :two_factor_email
  post 'two-factor-email/resend', to: 'email_two_factor_challenges#create', as: :resend_two_factor_email
  get 'two-factor-email/verify', to: 'email_two_factor_challenges#verify', as: :verify_two_factor_email

  # Public invitation routes (no auth required)
  get 'invitations/:token/accept', to: 'invitations#show', as: :accept_invitation
  post 'invitations/:token/accept', to: 'invitations#accept'

  # Main dashboard
  get 'dashboard', to: 'dashboard#index'
  post 'workspace/switch', to: 'workspace_switches#create', as: :workspace_switch
  get 'no-workspace', to: 'no_workspaces#show', as: :no_workspace

  # Team
  get 'team', to: 'team#index'

  # Customer AI Assistant
  # WHY: The concrete /assistant/chats/... routes are declared before the /assistant/:id deep link
  # so the `:id` segment can never swallow them; `:id` is also constrained to digits.
  get 'assistant', to: 'assistant#index', as: :assistant
  get 'assistant/chats', to: 'assistant#list_chats', as: :assistant_chat_list
  post 'assistant/chats', to: 'assistant#create', as: :assistant_chats
  delete 'assistant/chats/:id', to: 'assistant#destroy', as: :assistant_chat
  patch 'assistant/chats/:id/pin', to: 'assistant#pin', as: :assistant_chat_pin
  get 'assistant/prompts', to: 'assistant#list_prompts', as: :assistant_prompt_list
  post 'assistant/prompts', to: 'assistant#create_prompt', as: :assistant_prompts
  patch 'assistant/prompts/:id', to: 'assistant#update_prompt', as: :assistant_prompt
  delete 'assistant/prompts/:id', to: 'assistant#destroy_prompt', as: :assistant_prompt_destroy
  # WHY: POST appends a prompt; GET pages backwards through history via a `before_id` cursor.
  post 'assistant/chats/:id/messages', to: 'assistant#create_message', as: :assistant_chat_messages
  get 'assistant/chats/:id/messages', to: 'assistant#messages', as: :assistant_chat_older_messages
  get 'assistant/:id', to: 'assistant#index', as: :assistant_conversation, constraints: { id: /\d+/ }

  resources :replies, only: [:index], path: 'inbox' do
    member do
      post :mark_read
      post :update_interest_status
      post :close
      post :reopen
      post :snooze
    end
  end

  # Customer Meetings Center (AMP-136)
  resources :meetings, only: %i[index create] do
    collection do
      get :search_leads
    end

    member do
      post :assign
      get :lead_modal
      post :mark_completed
      post :mark_no_show
      post :reschedule
      post :set_outcome
      patch :update_notes
      post :request_removal
    end
  end

  # Customer ROI Dashboard (AMP-139)
  get 'roi', to: 'roi#index'
  patch 'roi', to: 'roi#update'

  # Customer Settings (AMP-140: Settings Page)
  namespace :settings do
    # Root redirect to first tab
    get '/', to: redirect('/settings/billing')

    # Settings tabs
    get 'billing', to: 'billing#index'
    post 'billing/notify_interest', to: 'billing#notify_interest'
    get 'profile', to: 'profile#index'
    patch 'profile', to: 'profile#update'
    patch 'profile/password', to: 'profile#update_password'
    get 'team', to: 'team#index'
    post 'team/invitations', to: 'team#create_invitation'
    delete 'team/invitations/:id', to: 'team#cancel_invitation', as: :team_invitation
    patch 'team/members/:id/deactivate', to: 'team#deactivate_member', as: :team_deactivate_member

    # Existing settings resources
    resource :company, only: %i[edit update], controller: 'company'
    resources :blacklists, only: %i[index create destroy] do
      collection do
        get :export
        post :import
      end
    end
  end

  # Customer Agents - accessible at /agents (controller: Customer::AgentsController)
  # Route helpers remain customer_agents_path, customer_agent_path, etc.
  scope module: :customer, as: :customer do
    get 'leads/:id/modal', to: 'agents#lead_modal', as: :lead_modal
    post 'leads/:id/update_interest_status', to: 'agents#update_interest_status', as: :lead_update_interest_status
    post 'leads/:id/open_reply_conversation', to: 'agents#open_reply_conversation', as: :lead_open_reply_conversation

    resources :agents, only: %i[index show] do
      collection do
        get :companies
        get :download
      end

      member do
        post :pause_campaign
        post :resume_campaign
      end
    end
  end

  # Locale switching (Week 2)
  post 'locale', to: 'locale#update'

  # Customer Playbooks (Week 3)
  resources :playbooks, only: %i[index show update] do
    member do
      post :approve
      post :request_changes
      post :archive
      post :upload_file
      get :import_leads, to: 'playbook_lead_imports#index'
      post :import_leads, to: 'playbook_lead_imports#create'
      get :import_leads_template, to: 'playbook_lead_imports#template'
      post :lead_list_files, to: 'playbook_lead_imports#upload_lead_list_file'
      get 'lead_list_files/:file_id/download', to: 'playbook_lead_imports#download_lead_list_file',
                                                as: :lead_list_file_download
      get 'knowledge-base', to: 'playbooks#knowledge_base', as: :knowledge_base
      post :knowledge_base_files
      get 'knowledge_base_files/:file_id/download', to: 'playbooks#download_knowledge_base_file',
                                                     as: :knowledge_base_file_download
    end

    resources :playbook_comments, only: [:create], path: 'comments'
  end

  # Super Admin
  namespace :admin do
    get 'dashboard', to: 'dashboard#index'

    resources :organizations do
      member do
        post :archive
      end

      resources :users, only: %i[index show new create edit update destroy],
                        controller: 'organizations/users' do
        member do
          post :send_reset_password_email
          post :set_password
        end
      end
    end
    resources :users do
      member do
        post :send_reset_password_email
        post :set_password
        post :add_organization_membership
        patch 'organization_memberships/:membership_id', to: 'users#update_organization_membership', as: :organization_membership
        delete 'organization_memberships/:membership_id', to: 'users#remove_organization_membership'
      end
    end
    resources :activities, only: %i[index show]

    # Invitations (Week 2)
    resources :invitations, only: %i[index new create destroy] do
      member do
        post :resend
        post :cancel
      end
    end

    # Impersonation
    post 'users/:id/impersonate', to: 'impersonation#create', as: 'impersonate'
    post 'impersonation/exit', to: 'impersonation#destroy', as: 'exit_impersonation'
  end

  # API namespace for AJAX/JSON endpoints
  namespace :api do
    namespace :v1 do
      resources :lead_imports, only: [:show]
    end
  end

  get '.well-known/oauth-protected-resource', to: 'mcp/oauth#protected_resource'
  get '.well-known/oauth-protected-resource/mcp', to: 'mcp/oauth#protected_resource'
  get '.well-known/oauth-authorization-server', to: 'mcp/oauth#authorization_server'
  get 'oauth/register/*client_id', to: 'mcp/oauth#client_registration'
  get 'oauth/register', to: 'mcp/oauth#client_registration'
  post 'oauth/register', to: 'mcp/oauth#register'
  post 'register', to: 'mcp/oauth#register'
  get 'oauth/authorize', to: 'mcp/oauth#authorize'
  post 'oauth/authorize', to: 'mcp/oauth#approve'
  post 'oauth/token', to: 'mcp/oauth#token'
  get 'mcp', to: 'mcp#show'
  post 'mcp', to: 'mcp#create'

  # Health check
  get 'up', to: 'rails/health#show', as: :rails_health_check
end
