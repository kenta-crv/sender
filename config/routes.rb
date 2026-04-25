Rails.application.routes.draw do
  # admin認証 (admins)
  devise_for :admins, controllers: {
    sessions: "admins/sessions",
    registrations: "admins/registrations",
    passwords: "admins/passwords"
  }
  namespace :admin do
    get 'dashboard/index'
    get 'dashboard/setting'
    get 'dashboard/history'
    root "dashboard#index"
    resources :notifications
  end
  
  # クライアント認証 (clients)
  devise_for :clients, controllers: {
    sessions: "clients/sessions",
    registrations: "clients/registrations",
    passwords: "clients/passwords"
  }
  namespace :client do
    get 'dashboard/index'
    get 'dashboard/setting'
    get 'dashboard/history'
    get 'dashboard/duplication'
    get 'dashboard/import'
    get 'dashboard/searching_form'
    get 'dashboard/sending'
    root "dashboard#index"
    resources :notifications
    
    get 'subscription', to: 'subscriptions#show', as: :subscription
    patch 'subscription', to: 'subscriptions#update'
    post 'subscription/cancel', to: 'subscriptions#cancel', as: :cancel
  end

  # クライアントリソース
  resources :clients do
    resources :push_subscriptions, only: [:index, :create]
  end

  # 決済関連 (詳細を1行ずつ維持)
  get 'checkout/confirmation', to: 'checkout#confirmation', as: :checkout_confirmation
  post 'checkout/create', to: 'checkout#create', as: :checkout_create
  get 'checkout/success', to: 'checkout#success', as: :checkout_success
  get 'checkout/cancel', to: 'checkout#cancel', as: :checkout_cancel

  # プラン選択
  get 'plans', to: 'plans#index', as: :plans
  post 'plans/select', to: 'plans#select', as: :select_plan

  devise_for :workers, controllers: {
    sessions: 'workers/sessions',
    registrations: 'workers/registrations'
  }
  resources :workers, only: [:show]


  root to: 'tops#index'
  get 'okurite', to: 'tops#okurite'
  get 'sales', to: 'tops#sales'

  # --- SEO用: ジャンル別コラム階層 (/genre/columns/:code) ---
  # constraintsに一致する場合、こちらのルーティングが優先されます
  scope ':genre', constraints: { genre: /app/ } do
    resources :columns, only: [:index, :show], as: :nested_columns
  end
  resources :contracts

  get 'draft/progress', to: 'draft#progress'

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

  resources :form_submissions, only: [:index, :create, :show, :destroy] do
    collection do
      post :import_customers 
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
    post 'stream_result', to: 'voice#stream_result'
    post 'stream_fallback', to: 'voice#stream_fallback'
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
      post :cleanup_duplicates
      post :serp_search
      get  :draft
      post :extract_company_info
      get  :extract_progress
      get  :filter_by_industry
      post :bulk_action
      post :import, to: 'customers#all_import'
    end
    resources :calls
  end
end