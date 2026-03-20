Rails.application.routes.draw do
  # Sidekiqを使わないため、マウント設定は残しても害はありませんが、プロセスは不要になります
  require 'sidekiq/web'
  mount Sidekiq::Web => '/sidekiq'

  root to: 'top#index'
  get "top/recruit" => 'top#recruit'
  get "top/recruit_jp" => 'top#recruit_jp'
  get "top/recruit_en" => 'top#recruit_en'
  get "top/recruit_clean" => 'top#recruit_clean'
  get "top/calculation" => 'top#calculation'  

  get 'information' => 'top#information'

  get "top/black" => 'top#black'
  
  get "top/flow" => 'top#flow'
  get "top/entry" => 'top#entry'
  get "top/attention" => 'top#attention'  
  get "top/apply" => 'top#apply'  

  get "top/policy" => 'top#policy'  

  get "/appointer" => 'top#appointer'
  get "/database" => 'top#database'
  get "/zero" => 'top#zero'
  get "/free" => 'top#free'
  get "/restaurant" => 'top#restaurant'
  get '/redirect', to: 'top#redirect'
  get 'users/thanks', to: 'users#thanks'
  get 'documents', to: 'top#documents'
  get 'databases', to: 'top#databases'
  get 'lp', to: 'top#lp'
  resources :access_logs, only: [:index]
   
  get 'line', to: 'top#line'

  devise_for :admins, controllers: {
    registrations: 'admins/registrations',
    sessions: 'admins/sessions'
  }
  resources :admins, only: [:show]

  resources :clients do
    resources :situations
    resources :jobs 
    collection do
      post :confirm
      post :thanks
    end
    member do
      post :send_mail
      post :send_mail_start
      get "conclusion"
    end
  end

  devise_for :users, controllers: {
    registrations: 'users/registrations',
    sessions: 'users/sessions'
  }

  resources :form_submissions, only: [:index, :create, :show, :destroy] do
    collection do
      post :bulk_call_ivr
      get :call
      post :confirm
      post :thanks
    end
    member do
      post :send_sms
      post :send_mail
      post :send_mail_start
      get "info"
      get "conclusion"
      get "payment"
      get "calendar"
      get "start"
      post :call_ivr
      # ★ 修正：show_ivrへのアクセスを IvrController#show に、handle_choice_ivrを IvrController#handle_choice に繋ぎます
      match 'show_ivr', to: 'ivr#show', as: :show_ivr, via: [:get, :post]
      post 'handle_choice_ivr', to: 'ivr#handle_choice', as: :handle_choice_ivr
   end
  end

  post "/api/v1/users/from_sheet", to: "api/v1/users#sheet_create"

  # 重複していた resources :ivr は削除しました。上記 users の member 内で完結させています。
end