Rails.application.routes.draw do
  # Deviseの管理者認証
  devise_for :admins, controllers: {
    sessions: 'admins/sessions',
    registrations: 'admins/registrations'
  }
  
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
  get 'ads', to: 'tops#ads'

  # --- SEO用: ジャンル別コラム階層 (/genre/columns/:code) ---
  # constraintsに一致する場合、こちらのルーティングが優先されます
  scope ':genre', constraints: { genre: /cargo|security|cleaning|app|construction/ } do
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

  resources :form_submissions, only: [:index, :create, :show] do
    collection do
      post :detect_contact_urls
    end
    member do
      patch :cancel
      get :progress
    end
  end

  resources :customers do
    resources :calls
  end
  get 'draft/filter_by_industry', to: 'customers#filter_by_industry', as: 'filter_by_industry'
  post 'draft/extract_company_info', to: 'customers#extract_company_info', as: 'extract_company_info'
  get 'draft/progress', to: 'customers#extract_progress', as: 'extract_progress'
  get 'draft' => 'customers#draft' #締め

end