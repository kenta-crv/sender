Rails.application.routes.draw do
  # Deviseの管理者認証
  devise_for :admins, controllers: {
    sessions: 'admins/sessions',
    registrations: 'admins/registrations'
  }
  resources :admins, only: [:show]
  
  devise_for :workers, controllers: {
    sessions: 'workers/sessions',
    registrations: 'workers/registrations'
  }
  resources :workers, only: [:show]

  root to: 'tops#index'

  # --- 各ジャンルLPの定義 ---
  get 'cargo', to: 'tops#cargo'
  get 'security', to: 'tops#security'
  get 'construction', to: 'tops#construction'
  get 'cleaning', to: 'tops#cleaning'
  get 'event', to: 'tops#event'
  get 'logistics', to: 'tops#logistics'
  get 'short', to: 'tops#short'
  get 'recruit', to: 'tops#recruit'
  get 'app', to: 'tops#app'
  get 'vender', to: 'tops#vender'
  get 'pest', to: 'tops#pest'
  get 'ads', to: 'tops#ads'

  # --- SEO用: ジャンル別コラム階層 (/genre/columns/:code) ---
  # constraintsに一致する場合、こちらのルーティングが優先されます
  scope ':genre', constraints: { genre: /cargo|security|cleaning|app|vender|pest|construction/ } do
    resources :columns, only: [:index, :show], as: :nested_columns
  end

  get 'draft/progress', to: 'draft#progress'

  resources :contracts
  # --- 管理機能・汎用リソースとしてのコラム ---
  # 基本的なCRUDはこちらを使用
  resources :columns do
    collection do
      get :draft            # ドラフト一覧
      post :generate_gemini # Gemini生成ボタンのPOST
      post :generate_pillar # 親専用生成ボタン
      match 'bulk_update_drafts', via: [:post, :patch]
    end
    member do
      patch :approve
    end
  end

  # --- Sidekiq Web UI ---
  require 'sidekiq/web'
  authenticate :admin do 
    mount Sidekiq::Web, at: "/sidekiq"
  end

resources :submissions do
  member do
    get :history
    get :manual
  end
end

  resources :form_submissions, only: [:index, :create, :show] do
    collection do
      post :detect_contact_urls
    end
    member do
      patch :update_manual
      patch :cancel
      post :resume
      get :progress
    end
  end

  # --- Twilio Webhooks ---
  namespace :twilio do
    post 'voice', to: 'voice#voice'
    post 'greeting', to: 'voice#greeting'
    post 'gather', to: 'voice#gather'
    post 'transfer', to: 'voice#transfer'
    post 'operator_join', to: 'voice#operator_join'
    post 'status', to: 'status#update'
    post 'recording_status', to: 'status#recording'
    post 'conference/status', to: 'conference#status'
  end

  # --- 自動発信バッチ管理 ---
  resources :call_batches do
    member do
      patch :pause
      patch :resume
      patch :cancel
      get :progress
    end
    collection do
      get :dashboard
    end
  end

  resources :customers do
    member do
      post :manual_call
    end
    collection do
      post :serp_search
      get  :draft
      post :extract_company_info
      get  :extract_progress
      get  :filter_by_industry
      post :bulk_action
    end
    resources :calls
  end
end