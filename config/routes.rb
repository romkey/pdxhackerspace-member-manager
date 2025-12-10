Rails.application.routes.draw do
  get 'default_settings/index'
  get 'default_settings/edit'
  get 'default_settings/update'
  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboard#index"

  get "/login", to: "sessions#new"
  post "/local_login", to: "sessions#create_local"
  post "/rfid_login", to: "sessions#create_rfid"
  get "/rfid_login/wait", to: "sessions#rfid_wait", as: :rfid_wait
  get "/rfid_login/verify", to: "sessions#rfid_verify", as: :rfid_verify
  get "/rfid_login/check_webhook", to: "sessions#rfid_check_webhook", as: :rfid_check_webhook
  post "/rfid_login/submit_pin", to: "sessions#rfid_submit_pin", as: :rfid_submit_pin
  delete "/logout", to: "sessions#destroy"
  match "/auth/:provider/callback", to: "sessions#create", via: %i[get post]
  get "/auth/failure", to: "sessions#failure"

  post "/webhooks/rfid", to: "webhooks#rfid"

  resources :users, only: [:index, :show, :edit, :update, :destroy] do
    member do
      post :activate
      post :deactivate
      post :ban
      post :mark_deceased
    end
    collection do
      post :sync
    end
  end

  resources :slack_users, only: [:index, :show] do
    collection do
      post :sync
      post :sync_to_users
    end
    member do
      post :link_user
    end
  end

  resources :sheet_entries, only: [:index, :show] do
    collection do
      post :sync
      post :sync_to_users
      get :test
    end
    member do
      post :sync_to_user
    end
  end

  resources :paypal_payments, only: [:index, :show] do
    collection do
      post :sync
      get :test
      get :export
      post :import
    end
    member do
      post :link_user
    end
  end

  resources :recharge_payments, only: [:index, :show] do
    collection do
      post :sync
      get :test
      get :export
      post :import
    end
    member do
      post :link_user
    end
  end

  resources :journals, only: [:index]

  resources :access_logs, only: [:index] do
    collection do
      get :generate_users_json
    end
  end

  get "/search", to: "search#index", as: :search

  get "/settings", to: "settings#index", as: :settings
  resources :training_topics, only: [:index, :create, :destroy]
  resources :membership_plans, except: [:show]
  resources :rfid_readers, except: [:show] do
    member do
      post :regenerate_key
    end
  end
  resource :default_settings, only: [:show, :edit, :update], path: "settings/defaults"
  
  get "/reports", to: "reports#index", as: :reports
  get "/reports/:report_type/all", to: "reports#view_all", as: :reports_view_all
  post "/reports/update_user", to: "reports#update_user", as: :reports_update_user
  
  require 'sidekiq/web'
  mount Sidekiq::Web => '/goh7zeeNiezoozaingothu4'
  
  resources :applications do
    resources :application_groups, except: [:index] do
      member do
        post :add_user
        delete :remove_user
      end
    end
  end
end
